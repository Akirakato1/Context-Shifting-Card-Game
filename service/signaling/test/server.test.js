import assert from "node:assert/strict";
import http from "node:http";
import test from "node:test";
import { WebSocket } from "ws";

import {
  MAX_MESSAGE_BYTES,
  MessageRateLimiter,
  decodeClientMessage,
} from "../src/protocol.js";
import { createSignalingServer } from "../src/server.js";

function nextMessage(socket) {
  return new Promise((resolve, reject) => {
    const onMessage = (data) => {
      cleanup();
      resolve(JSON.parse(data.toString("utf8")));
    };
    const onError = (error) => {
      cleanup();
      reject(error);
    };
    const cleanup = () => {
      socket.off("message", onMessage);
      socket.off("error", onError);
    };
    socket.on("message", onMessage);
    socket.on("error", onError);
  });
}

function connect(url) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    socket.once("open", () => resolve(socket));
    socket.once("error", reject);
  });
}

function get(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (response) => {
      let body = "";
      response.setEncoding("utf8");
      response.on("data", (chunk) => {
        body += chunk;
      });
      response.on("end", () => resolve({ status: response.statusCode, body }));
    }).on("error", reject);
  });
}

function send(socket, message) {
  socket.send(JSON.stringify({ v: 1, ...message }));
}

test("protocol decoder rejects malformed, oversized, unknown, and invalid-role messages", () => {
  assert.equal(decodeClientMessage(Buffer.from("{" )).error, "malformed_json");
  assert.equal(
    decodeClientMessage(Buffer.alloc(MAX_MESSAGE_BYTES + 1, 65)).error,
    "message_too_large",
  );
  assert.equal(
    decodeClientMessage(Buffer.from(JSON.stringify({ v: 2, type: "host_room" }))).error,
    "unsupported_version",
  );
  assert.equal(
    decodeClientMessage(Buffer.from(JSON.stringify({ v: 1, type: "game_state" }))).error,
    "unknown_message_type",
  );
  assert.equal(
    decodeClientMessage(Buffer.from(JSON.stringify({
      v: 1,
      type: "join_room",
      code: "ABC222",
      role: "admin",
    }))).error,
    "invalid_role",
  );
});

test("message rate limiter uses a deterministic bounded window", () => {
  let now = 0;
  const limiter = new MessageRateLimiter({ limit: 2, windowMs: 1000, now: () => now });
  const socket = {};

  assert.equal(limiter.accept(socket), true);
  assert.equal(limiter.accept(socket), true);
  assert.equal(limiter.accept(socket), false);
  now = 1000;
  assert.equal(limiter.accept(socket), true);
});

test("HTTP health and host-approved signaling route without accepting gameplay", async (t) => {
  let token = 0;
  const server = createSignalingServer({
    codeGenerator: () => "ABC234",
    tokenGenerator: () => `token-${++token}`,
  });
  const address = await server.listen(0, "127.0.0.1");
  t.after(async () => server.close());
  const httpUrl = `http://127.0.0.1:${address.port}`;
  const wsUrl = `ws://127.0.0.1:${address.port}`;

  const health = await get(`${httpUrl}/health`);
  assert.equal(health.status, 200);
  assert.deepEqual(JSON.parse(health.body), { ok: true, service: "shift-signaling", v: 1 });

  const host = await connect(wsUrl);
  const joiner = await connect(wsUrl);
  t.after(() => host.close());
  t.after(() => joiner.close());

  const roomCreatedPromise = nextMessage(host);
  send(host, { type: "host_room" });
  const roomCreated = await roomCreatedPromise;
  assert.equal(roomCreated.type, "room_created");

  const hostJoinPromise = nextMessage(host);
  const joinPendingPromise = nextMessage(joiner);
  send(joiner, { type: "join_room", code: roomCreated.code.toLowerCase(), role: "active" });
  const [hostJoin, joinPending] = await Promise.all([hostJoinPromise, joinPendingPromise]);
  assert.equal(hostJoin.type, "join_requested");
  assert.equal(joinPending.type, "join_pending");
  assert.equal(hostJoin.join_nonce, joinPending.join_nonce);

  const preapprovalErrorPromise = nextMessage(joiner);
  send(joiner, {
    type: "offer",
    code: roomCreated.code,
    join_nonce: joinPending.join_nonce,
    payload: { sdp: "not-yet-authorized" },
  });
  assert.equal((await preapprovalErrorPromise).error, "join_not_approved");

  const approvedPromise = nextMessage(joiner);
  send(host, {
    type: "approve_join",
    code: roomCreated.code,
    host_token: roomCreated.host_token,
    join_nonce: joinPending.join_nonce,
  });
  const approved = await approvedPromise;
  assert.equal(approved.type, "join_approved");
  assert.equal(approved.peer_id, hostJoin.peer_id);

  const routedOfferPromise = nextMessage(host);
  send(joiner, {
    type: "offer",
    code: roomCreated.code,
    join_nonce: joinPending.join_nonce,
    payload: { sdp: "offer-sdp" },
  });
  const routedOffer = await routedOfferPromise;
  assert.deepEqual(routedOffer.payload, { sdp: "offer-sdp" });
  assert.equal(routedOffer.peer_id, approved.peer_id);

  const wrongNoncePromise = nextMessage(joiner);
  send(joiner, {
    type: "ice_candidate",
    code: roomCreated.code,
    join_nonce: "wrong",
    payload: { candidate: "candidate" },
  });
  assert.equal((await wrongNoncePromise).error, "invalid_join_nonce");

  const gameplayPromise = nextMessage(joiner);
  send(joiner, { type: "game_state", payload: { hands: ["secret"] } });
  assert.equal((await gameplayPromise).error, "unknown_message_type");

  const forbiddenClosePromise = nextMessage(joiner);
  send(joiner, { type: "close_room", code: roomCreated.code });
  assert.equal((await forbiddenClosePromise).error, "host_authorization_required");

  const roomClosedPromise = nextMessage(joiner);
  host.close();
  assert.equal((await roomClosedPromise).type, "room_closed");
});
