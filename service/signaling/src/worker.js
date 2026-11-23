import { DurableObject } from "cloudflare:workers";

import { createIceServerProvider } from "./ice_server_provider.js";
import { MessageRateLimiter, decodeClientMessage } from "./protocol.js";
import { RoomRegistry, RoomRegistryError } from "./room_registry.js";
import { handleMessage, healthPayload, send, sendError } from "./signaling_session.js";

const HUB_NAME = "shift-signaling";

function isWebSocketRequest(request) {
  return request.method === "GET" && request.headers.get("upgrade")?.toLowerCase() === "websocket";
}

function notFound() {
  return Response.json({ ok: false, error: "not_found" }, { status: 404 });
}

export default {
  fetch(request, env) {
    if (request.method === "GET" && new URL(request.url).pathname === "/health") {
      return Response.json(healthPayload(createIceServerProvider({ env })));
    }
    if (isWebSocketRequest(request)) {
      return env.SIGNALING_HUB.getByName(HUB_NAME).fetch(request);
    }
    return notFound();
  },
};

export class SignalingHub extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.provider = createIceServerProvider({ env });
    this.limiter = new MessageRateLimiter();
    this.messageQueues = new WeakMap();
    this.registry = new RoomRegistry({
      onRoomChanged: (code, room) => this.persistRoom(code, room),
      onDetachedHostExpired: ({ code, peerSockets }) => {
        for (const socket of peerSockets) {
          send(socket, "room_closed", { code });
        }
      },
    });
    this.sql.exec(`CREATE TABLE IF NOT EXISTS rooms (
      code TEXT PRIMARY KEY,
      room TEXT NOT NULL,
      expires_at INTEGER
    )`);
    this.restoreRooms(ctx.getWebSockets());
  }

  fetch(request) {
    if (!isWebSocketRequest(request)) {
      return notFound();
    }
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment(crypto.randomUUID());
    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(socket, raw) {
    if (!this.limiter.accept(socket)) {
      sendError(socket, "rate_limit_exceeded");
      socket.close(1008, "rate_limit_exceeded");
      return;
    }
    const decoded = decodeClientMessage(raw);
    if (!decoded.ok) {
      if (decoded.error === "message_too_large") {
        socket.close(1009, "message_too_large");
      } else {
        sendError(socket, decoded.error);
      }
      return;
    }
    const previous = this.messageQueues.get(socket) ?? Promise.resolve();
    const next = previous.then(() => {
      if (socket.readyState === 1) {
        return handleMessage(this.registry, this.provider, socket, decoded.message);
      }
    }).catch((error) => {
      sendError(socket, error instanceof RoomRegistryError ? error.code : "internal_error");
    });
    this.messageQueues.set(socket, next);
    return next;
  }

  webSocketClose(socket, code, reason) {
    if ((code >= 1000 && code <= 1014 && ![1004, 1005, 1006].includes(code))
      || (code >= 3000 && code <= 4999)) {
      socket.close(code, reason);
    } else {
      socket.close();
    }
    const result = this.registry.removeSocket(socket);
    if (result.hostDetached) {
      return this.scheduleExpiry();
    }
  }

  webSocketError(socket) {
    return this.webSocketClose(socket);
  }

  alarm() {
    const now = Date.now();
    const expired = this.sql.exec("SELECT room FROM rooms WHERE expires_at <= ?", now).toArray();
    for (const row of expired) {
      const { code, hostToken } = JSON.parse(row.room);
      this.registry.expireDetachedHost(code, hostToken);
    }
    return this.scheduleExpiry();
  }

  persistRoom(code, room) {
    if (room === null) {
      this.sql.exec("DELETE FROM rooms WHERE code = ?", code);
      return;
    }
    // Socket attachments keep the same identity after the Durable Object wakes.
    const record = {
      ...room,
      hostSocket: room.hostSocket?.deserializeAttachment() ?? null,
      joins: [...room.joins.values()].map((join) => ({
        ...join, socket: join.socket.deserializeAttachment(),
      })),
    };
    const expiresAt = room.hostDetachedAt === null
      ? null
      : room.hostDetachedAt + this.registry.hostReconnectGraceMs;
    this.sql.exec(
      "INSERT OR REPLACE INTO rooms (code, room, expires_at) VALUES (?, ?, ?)",
      code, JSON.stringify(record), expiresAt,
    );
  }

  restoreRooms(webSockets) {
    const sockets = new Map(webSockets.map((socket) => [socket.deserializeAttachment(), socket]));
    for (const { room } of this.sql.exec("SELECT room FROM rooms").toArray()) {
      const record = JSON.parse(room);
      const hostSocket = sockets.get(record.hostSocket) ?? null;
      const hostMissing = record.hostSocket !== null && hostSocket === null;
      const joins = new Map();
      for (const join of record.joins) {
        const socket = sockets.get(join.socket);
        if (socket) {
          joins.set(join.joinNonce, { ...join, socket });
        }
      }
      const restored = {
        ...record, hostSocket, joins,
        hostDetachedAt: hostMissing ? Date.now() : record.hostDetachedAt,
      };
      this.registry.restoreRoom(restored);
      if (hostMissing || joins.size !== record.joins.length) {
        this.persistRoom(restored.code, restored);
      }
    }
    if (this.sql.exec("SELECT 1 FROM rooms WHERE expires_at IS NOT NULL LIMIT 1").toArray().length) {
      this.ctx.blockConcurrencyWhile(async () => {
        if (await this.ctx.storage.getAlarm() === null) {
          await this.scheduleExpiry();
        }
      });
    }
  }

  scheduleExpiry() {
    const { next } = this.sql.exec("SELECT MIN(expires_at) AS next FROM rooms").one();
    if (next !== null) {
      return this.ctx.storage.setAlarm(next);
    }
    return Promise.resolve();
  }
}
