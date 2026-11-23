import http from "node:http";
import { fileURLToPath } from "node:url";
import { WebSocketServer } from "ws";

import { MAX_MESSAGE_BYTES, MessageRateLimiter, decodeClientMessage } from "./protocol.js";
import { createIceServerProvider } from "./ice_server_provider.js";
import { RoomRegistry, RoomRegistryError } from "./room_registry.js";
import { handleMessage, healthPayload, send, sendError } from "./signaling_session.js";

export function createSignalingServer(options = {}) {
  const registry = new RoomRegistry(options);
  const iceServerProvider = options.iceServerProvider ?? createIceServerProvider();
  const limiter = new MessageRateLimiter({
    limit: options.rateLimit ?? 120,
    windowMs: options.rateWindowMs ?? 10_000,
    now: options.now,
  });
  const httpServer = http.createServer((request, response) => {
    if (request.method === "GET" && request.url === "/health") {
      response.writeHead(200, { "content-type": "application/json; charset=utf-8" });
      response.end(JSON.stringify(healthPayload(iceServerProvider)));
      return;
    }
    response.writeHead(404, { "content-type": "application/json; charset=utf-8" });
    response.end(JSON.stringify({ ok: false, error: "not_found" }));
  });
  const wsServer = new WebSocketServer({ server: httpServer, maxPayload: MAX_MESSAGE_BYTES });

  wsServer.on("connection", (socket) => {
    let messageQueue = Promise.resolve();
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
      messageQueue = messageQueue
        .then(() => handleMessage(registry, iceServerProvider, socket, decoded.message))
        .catch((error) => {
        if (error instanceof RoomRegistryError) {
          sendError(socket, error.code);
          return;
        }
        sendError(socket, "internal_error");
        });
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

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) {
  const port = Number.parseInt(process.env.PORT ?? "8080", 10);
  const server = createSignalingServer();
  server.listen(port, "0.0.0.0").then((address) => {
    console.log(`shift-signaling listening on ${address.address}:${address.port}`);
  });
}
