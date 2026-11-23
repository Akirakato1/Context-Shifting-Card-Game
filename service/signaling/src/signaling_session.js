import { PROTOCOL_VERSION, serverMessage } from "./protocol.js";
import { fallbackIceServers, normalizeIceServers } from "./ice_server_provider.js";
import { RoomRegistryError } from "./room_registry.js";

export function send(socket, type, fields = {}) {
  if (socket?.readyState === 1) {
    socket.send(serverMessage(type, fields));
  }
}

export function sendError(socket, error) {
  send(socket, "error", { error });
}

export function healthPayload(provider) {
  return {
    ok: true,
    service: "shift-signaling",
    v: PROTOCOL_VERSION,
    relay: {
      provider: typeof provider.name === "string" ? provider.name : "unknown",
      configured: provider.configured === true,
    },
  };
}

async function icePayload(provider) {
  try {
    const iceServers = normalizeIceServers(await provider.getIceServers());
    const relayAvailable = iceServers.some((entry) => (
      typeof entry.username === "string"
      && entry.urls.some((url) => /^(?:turn|turns):/i.test(url))
    ));
    return { ice_servers: iceServers, relay_available: relayAvailable };
  } catch {
    return { ice_servers: fallbackIceServers(), relay_available: false };
  }
}

export async function handleMessage(registry, provider, socket, message) {
  if (message.type === "host_room") {
    if (message.reconnect === true) {
      const { code } = registry.reconnectHost(
        socket,
        message.code,
        message.host_token,
      );
      send(socket, "room_created", {
        code,
        host_token: message.host_token,
        ...await icePayload(provider),
      });
      return;
    }
    const { code, hostToken } = registry.createHost(socket);
    send(socket, "room_created", {
      code,
      host_token: hostToken,
      ...await icePayload(provider),
    });
    return;
  }
  if (message.type === "join_room") {
    const room = registry.inspectRoom(message.code);
    if (!room) {
      throw new RoomRegistryError("room_not_found");
    }
    const { joinNonce, peerId } = registry.requestJoin(
      message.code, message.role, socket, message.display_name,
      message.reconnect_player_id ?? "",
    );
    const reconnectFields = message.reconnect_player_id
      ? { reconnect_player_id: message.reconnect_player_id }
      : {};
    send(socket, "join_pending", {
      code: room.code,
      role: message.role,
      join_nonce: joinNonce,
      peer_id: peerId,
      display_name: message.display_name,
      ...reconnectFields,
    });
    send(room.hostSocket, "join_requested", {
      code: room.code,
      role: message.role,
      join_nonce: joinNonce,
      peer_id: peerId,
      display_name: message.display_name,
      ...reconnectFields,
    });
    return;
  }
  if (message.type === "approve_join") {
    const approved = registry.approveJoin(message.code, message.host_token, message.join_nonce);
    send(approved.socket, "join_approved", {
      code: String(message.code).toUpperCase(),
      role: approved.role,
      join_nonce: message.join_nonce,
      peer_id: approved.peerId,
      display_name: approved.displayName,
      ...(approved.reconnectPlayerId
        ? { reconnect_player_id: approved.reconnectPlayerId }
        : {}),
      ...await icePayload(provider),
    });
    return;
  }
  if (["offer", "answer", "ice_candidate"].includes(message.type)) {
    if (message.join_nonce) {
      const route = registry.joinRouteStatus(socket, message.code, message.join_nonce);
      if (!route.ok) {
        sendError(socket, route.error);
        return;
      }
      send(route.room.hostSocket, message.type, {
        code: route.room.code,
        peer_id: route.join.peerId,
        payload: message.payload,
      });
      return;
    }
    const route = registry.hostRoute(message.code, message.host_token, message.peer_id);
    if (route.room.hostSocket !== socket) {
      throw new RoomRegistryError("host_authorization_required");
    }
    send(route.join.socket, message.type, {
      code: route.room.code,
      peer_id: route.join.peerId,
      payload: message.payload,
    });
    return;
  }
  if (message.type === "close_room") {
    if (!message.host_token || !registry.isHost(socket, message.code, message.host_token)) {
      throw new RoomRegistryError("host_authorization_required");
    }
    const result = registry.closeHost(socket);
    for (const peerSocket of result.peerSockets) {
      send(peerSocket, "room_closed", { code: result.code });
    }
    send(socket, "room_closed", { code: result.code });
  }
}
