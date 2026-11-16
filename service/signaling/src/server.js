import http from "node:http";
import { fileURLToPath } from "node:url";
import { WebSocket, WebSocketServer } from "ws";

import {
  MAX_MESSAGE_BYTES,
  MessageRateLimiter,
  PROTOCOL_VERSION,
  decodeClientMessage,
  serverMessage,
} from "./protocol.js";
import { RoomRegistry, RoomRegistryError } from "./room_registry.js";

function send(socket, type, fields = {}) {
  if (socket.readyState === WebSocket.OPEN) {
    socket.send(serverMessage(type, fields));
  }
}

function sendError(socket, error) {
  send(socket, "error", { error });
}

export function createSignalingServer(options = {}) {
  const registry = new RoomRegistry(options);
  const limiter = new MessageRateLimiter({
    limit: options.rateLimit ?? 120,
    windowMs: options.rateWindowMs ?? 10_000,
    now: options.now,
  });
  const httpServer = http.createServer((request, response) => {
    if (request.method === "GET" && request.url === "/health") {
      response.writeHead(200, { "content-type": "application/json; charset=utf-8" });
      response.end(JSON.stringify({ ok: true, service: "shift-signaling", v: PROTOCOL_VERSION }));
      return;
    }
    response.writeHead(404, { "content-type": "application/json; charset=utf-8" });
    response.end(JSON.stringify({ ok: false, error: "not_found" }));
  });
  const wsServer = new WebSocketServer({ server: httpServer, maxPayload: MAX_MESSAGE_BYTES });

  wsServer.on("connection", (socket) => {
    socket.on("error", () => {
      // Protocol and frame errors belong to this connection. `ws` closes the
      // offending socket itself; consuming the event keeps the service alive.
    });

    socket.on("message", (raw) => {
      if (!limiter.accept(socket)) {
        sendError(socket, "rate_limit_exceeded");
        socket.close(1008, "rate_limit_exceeded");
        return;
      }
      const decoded = decodeClientMessage(raw);
      if (!decoded.ok) {
        sendError(socket, decoded.error);
        return;
      }
      try {
        handleMessage(registry, socket, decoded.message);
      } catch (error) {
        if (error instanceof RoomRegistryError) {
          sendError(socket, error.code);
          return;
        }
        sendError(socket, "internal_error");
      }
    });

    socket.on("close", () => {
      try {
        const result = registry.removeSocket(socket);
        if (result.hostClosed) {
          for (const peerSocket of result.peerSockets) {
            send(peerSocket, "room_closed", { code: result.code });
          }
        } else if (result.hostDetached) {
          const timer = setTimeout(() => {
            const expired = registry.expireDetachedHost(result.code, result.hostToken);
            if (expired) {
              for (const peerSocket of expired.peerSockets) {
                send(peerSocket, "room_closed", { code: expired.code });
              }
            }
          }, registry.hostReconnectGraceMs);
          timer.unref();
        }
      } catch {
        // Socket close is idempotent and must not take down the service.
      }
    });
  });

  return {
    registry,
    httpServer,
    wsServer,
    listen(port, host) {
      return new Promise((resolve, reject) => {
        httpServer.once("error", reject);
        httpServer.listen(port, host, () => {
          httpServer.off("error", reject);
          resolve(httpServer.address());
        });
      });
    },
    close() {
      return new Promise((resolve) => {
        for (const client of wsServer.clients) {
          client.terminate();
        }
        wsServer.close(() => {
          if (!httpServer.listening) {
            resolve();
            return;
          }
          httpServer.close(() => resolve());
        });
      });
    },
  };
}

function handleMessage(registry, socket, message) {
  if (message.type === "host_room") {
    if (message.reconnect === true) {
      const { code } = registry.reconnectHost(
        socket,
        message.code,
        message.host_token,
      );
      send(socket, "room_created", { code, host_token: message.host_token });
      return;
    }
    const { code, hostToken } = registry.createHost(socket);
    send(socket, "room_created", { code, host_token: hostToken });
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

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) {
  const port = Number.parseInt(process.env.PORT ?? "8080", 10);
  const server = createSignalingServer();
  server.listen(port, "0.0.0.0").then((address) => {
    console.log(`shift-signaling listening on ${address.address}:${address.port}`);
  });
}
