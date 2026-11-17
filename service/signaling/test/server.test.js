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

const TEST_ICE_SERVER_PROVIDER = {
  name: "none",
  configured: false,
  async getIceServers() {
    return [{ urls: ["stun:stun.l.google.com:19302"] }];
  },
};

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

function nextMessages(socket, count) {
  return new Promise((resolve, reject) => {
    const messages = [];
    const onMessage = (data) => {
      messages.push(JSON.parse(data.toString("utf8")));
      if (messages.length === count) {
        cleanup();
        resolve(messages);
      }
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

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

async function waitForCondition(condition, description, timeoutMs = 1000) {
  const startedAt = Date.now();
  while (!condition()) {
    if (Date.now() - startedAt > timeoutMs) {
      throw new Error(`Timed out waiting for ${description}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

function temporaryIceServers(label) {
  return [
    { urls: ["stun:stun.cloudflare.com:3478"] },
    {
      urls: ["turn:turn.cloudflare.com:3478?transport=udp"],
      username: `temporary-${label}`,
      credential: `credential-${label}`,
    },
  ];
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

function nextClose(socket) {
  return new Promise((resolve) => {
    socket.once("close", (code, reason) => resolve({ code, reason: reason.toString("utf8") }));
  });
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
  assert.equal(
    decodeClientMessage(Buffer.from(JSON.stringify({
      v: 1,
      type: "host_room",
      reconnect: true,
      code: "ABC222",
    }))).error,
    "malformed_message",
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

test("oversized websocket frames close only the offending socket", async (t) => {
  const server = createSignalingServer({
    codeGenerator: () => "BIG234",
    iceServerProvider: TEST_ICE_SERVER_PROVIDER,
  });
  const address = await server.listen(0, "127.0.0.1");
  t.after(async () => server.close());
  const httpUrl = `http://127.0.0.1:${address.port}`;
  const wsUrl = `ws://127.0.0.1:${address.port}`;

  const attacker = await connect(wsUrl);
  const attackerClosed = nextClose(attacker);
  attacker.send(Buffer.alloc(MAX_MESSAGE_BYTES + 1, 65));
  assert.equal((await attackerClosed).code, 1009);

  const health = await get(`${httpUrl}/health`);
  assert.equal(health.status, 200);

  const host = await connect(wsUrl);
  t.after(() => host.close());
  const roomCreatedPromise = nextMessage(host);
  send(host, { type: "host_room" });
  assert.equal((await roomCreatedPromise).type, "room_created");
});

test("HTTP health and host-approved signaling route without accepting gameplay", async (t) => {
  let token = 0;
  const server = createSignalingServer({
    codeGenerator: () => "ABC234",
    tokenGenerator: () => `token-${++token}`,
    iceServerProvider: TEST_ICE_SERVER_PROVIDER,
  });
  const address = await server.listen(0, "127.0.0.1");
  t.after(async () => server.close());
  const httpUrl = `http://127.0.0.1:${address.port}`;
  const wsUrl = `ws://127.0.0.1:${address.port}`;

  const health = await get(`${httpUrl}/health`);
  assert.equal(health.status, 200);
  assert.deepEqual(JSON.parse(health.body), {
    ok: true,
    service: "shift-signaling",
    v: 1,
    relay: { provider: "none", configured: false },
  });

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
  send(joiner, {
    type: "join_room", code: roomCreated.code.toLowerCase(), role: "active",
    display_name: "Mira", reconnect_player_id: "old-player",
  });
  const [hostJoin, joinPending] = await Promise.all([hostJoinPromise, joinPendingPromise]);
  assert.equal(hostJoin.type, "join_requested");
  assert.equal(hostJoin.display_name, "Mira");
  assert.equal(hostJoin.reconnect_player_id, "old-player");
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
  assert.equal(approved.display_name, "Mira");
  assert.equal(approved.reconnect_player_id, "old-player");

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

  host.close();
  await new Promise((resolve) => host.once("close", resolve));
  const replacementHost = await connect(wsUrl);
  t.after(() => replacementHost.close());
  const recreatedPromise = nextMessage(replacementHost);
  send(replacementHost, {
    type: "host_room",
    code: roomCreated.code,
    host_token: roomCreated.host_token,
    reconnect: true,
  });
  const recreated = await recreatedPromise;
  assert.equal(recreated.type, "room_created");
  assert.equal(recreated.code, roomCreated.code);

  const roomClosedPromise = nextMessage(joiner);
  send(replacementHost, {
    type: "close_room",
    code: roomCreated.code,
    host_token: roomCreated.host_token,
  });
  assert.equal((await roomClosedPromise).type, "room_closed");
});

test("health reports relay configuration without identifiers or secrets", async (t) => {
  const provider = {
    name: "cloudflare",
    configured: true,
    keyId: "must-not-leak-key-id",
    apiToken: "must-not-leak-api-token",
    async getIceServers() {
      throw new Error("health must not issue credentials");
    },
  };
  const server = createSignalingServer({ iceServerProvider: provider });
  const address = await server.listen(0, "127.0.0.1");
  t.after(async () => server.close());

  const health = await get(`http://127.0.0.1:${address.port}/health`);
  assert.equal(health.status, 200);
  assert.deepEqual(JSON.parse(health.body), {
    ok: true,
    service: "shift-signaling",
    v: 1,
    relay: { provider: "cloudflare", configured: true },
  });
  assert.doesNotMatch(health.body, /must-not-leak-key-id|must-not-leak-api-token/);
});

test("host and approved joiner receive distinct temporary ICE credentials", async (t) => {
  let issueCount = 0;
  const provider = {
    name: "cloudflare",
    configured: true,
    async getIceServers() {
      issueCount += 1;
      return temporaryIceServers(issueCount);
    },
  };
  const server = createSignalingServer({
    codeGenerator: () => "ICE234",
    iceServerProvider: provider,
  });
  const address = await server.listen(0, "127.0.0.1");
  t.after(async () => server.close());
  const wsUrl = `ws://127.0.0.1:${address.port}`;
  const host = await connect(wsUrl);
  const joiner = await connect(wsUrl);

  const createdPromise = nextMessage(host);
  send(host, { type: "host_room" });
  const created = await createdPromise;
  assert.equal(created.relay_available, true);
  assert.deepEqual(created.ice_servers, [
    { urls: ["stun:stun.cloudflare.com:3478"] },
    {
      urls: ["turn:turn.cloudflare.com:3478?transport=udp"],
      username: "temporary-1",
      credential: "credential-1",
    },
  ]);

  const requestedPromise = nextMessage(host);
  const pendingPromise = nextMessage(joiner);
  send(joiner, {
    type: "join_room",
    code: created.code,
    role: "active",
    display_name: "Mira",
  });
  const [requested, pending] = await Promise.all([requestedPromise, pendingPromise]);
  assert.equal(Object.hasOwn(pending, "ice_servers"), false);
  assert.equal(Object.hasOwn(requested, "ice_servers"), false);

  const approvedPromise = nextMessage(joiner);
  send(host, {
    type: "approve_join",
    code: created.code,
    host_token: created.host_token,
    join_nonce: pending.join_nonce,
  });
  const approved = await approvedPromise;
  assert.equal(approved.relay_available, true);
  assert.equal(approved.ice_servers[1].username, "temporary-2");
  assert.equal(approved.ice_servers[1].credential, "credential-2");
  assert.equal(issueCount, 2);
});

test("host reconnect and re-approved player obtain fresh ICE credentials", async (t) => {
  let issueCount = 0;
  let tokenCount = 0;
  const provider = {
    name: "cloudflare",
    configured: true,
    async getIceServers() {
      issueCount += 1;
      return temporaryIceServers(issueCount);
    },
  };
  const server = createSignalingServer({
    codeGenerator: () => "NEW234",
    tokenGenerator: () => `token-${++tokenCount}`,
    iceServerProvider: provider,
  });
  const address = await server.listen(0, "127.0.0.1");
  t.after(async () => server.close());
  const wsUrl = `ws://127.0.0.1:${address.port}`;

  const host = await connect(wsUrl);
  const createdPromise = nextMessage(host);
  send(host, { type: "host_room" });
  const created = await createdPromise;
  assert.equal(created.ice_servers[1].username, "temporary-1");
  host.close();
  await new Promise((resolve) => host.once("close", resolve));

  const replacementHost = await connect(wsUrl);
  const recreatedPromise = nextMessage(replacementHost);
  send(replacementHost, {
    type: "host_room",
    code: created.code,
    host_token: created.host_token,
    reconnect: true,
  });
  const recreated = await recreatedPromise;
  assert.equal(recreated.ice_servers[1].username, "temporary-2");

  const firstJoiner = await connect(wsUrl);
  const firstRequestedPromise = nextMessage(replacementHost);
  const firstPendingPromise = nextMessage(firstJoiner);
  send(firstJoiner, {
    type: "join_room",
    code: created.code,
    role: "active",
    display_name: "Mira",
    reconnect_player_id: "player-2",
  });
  const [firstRequested, firstPending] = await Promise.all([
    firstRequestedPromise,
    firstPendingPromise,
  ]);
  const firstApprovedPromise = nextMessage(firstJoiner);
  send(replacementHost, {
    type: "approve_join",
    code: created.code,
    host_token: created.host_token,
    join_nonce: firstRequested.join_nonce,
  });
  assert.equal((await firstApprovedPromise).ice_servers[1].username, "temporary-3");
  firstJoiner.close();
  await new Promise((resolve) => firstJoiner.once("close", resolve));

  const secondJoiner = await connect(wsUrl);
  const secondRequestedPromise = nextMessage(replacementHost);
  const secondPendingPromise = nextMessage(secondJoiner);
  send(secondJoiner, {
    type: "join_room",
    code: created.code,
    role: "active",
    display_name: "Mira",
    reconnect_player_id: "player-2",
  });
  const [secondRequested, secondPending] = await Promise.all([
    secondRequestedPromise,
    secondPendingPromise,
  ]);
  assert.equal(secondPending.reconnect_player_id, "player-2");
  const secondApprovedPromise = nextMessage(secondJoiner);
  send(replacementHost, {
    type: "approve_join",
    code: created.code,
    host_token: created.host_token,
    join_nonce: secondRequested.join_nonce,
  });
  assert.equal((await secondApprovedPromise).ice_servers[1].username, "temporary-4");
  assert.equal(issueCount, 4);
  assert.notEqual(firstPending.join_nonce, secondPending.join_nonce);
});

test("provider rejection or malformed output falls back to STUN without blocking room creation or approval", async () => {
  const providers = [
    {
      name: "cloudflare",
      configured: true,
      async getIceServers() {
        throw new Error("private-api-token must not leak");
      },
    },
    {
      name: "cloudflare",
      configured: true,
      async getIceServers() {
        return [{ urls: [] }];
      },
    },
  ];

  for (const [index, provider] of providers.entries()) {
    const server = createSignalingServer({
      codeGenerator: () => `BAD23${index + 4}`,
      iceServerProvider: provider,
    });
    const address = await server.listen(0, "127.0.0.1");
    const wsUrl = `ws://127.0.0.1:${address.port}`;
    try {
      const host = await connect(wsUrl);
      const joiner = await connect(wsUrl);
      const createdPromise = nextMessage(host);
      send(host, { type: "host_room" });
      const created = await createdPromise;
      assert.equal(created.relay_available, false);
      assert.deepEqual(created.ice_servers, [
        { urls: ["stun:stun.l.google.com:19302"] },
      ]);
      assert.doesNotMatch(JSON.stringify(created), /private-api-token/);

      const requestedPromise = nextMessage(host);
      const pendingPromise = nextMessage(joiner);
      send(joiner, {
        type: "join_room",
        code: created.code,
        role: "active",
        display_name: "Fallback",
      });
      const [requested, pending] = await Promise.all([requestedPromise, pendingPromise]);
      const approvedPromise = nextMessage(joiner);
      send(host, {
        type: "approve_join",
        code: created.code,
        host_token: created.host_token,
        join_nonce: requested.join_nonce,
      });
      const approved = await approvedPromise;
      assert.equal(approved.join_nonce, pending.join_nonce);
      assert.equal(approved.relay_available, false);
      assert.deepEqual(approved.ice_servers, [
        { urls: ["stun:stun.l.google.com:19302"] },
      ]);
    } finally {
      await server.close();
    }
  }
});

test("asynchronous credential issuance preserves message order and handles a closed socket", async (t) => {
  const firstIssue = deferred();
  const closedIssue = deferred();
  let issueCount = 0;
  const provider = {
    name: "cloudflare",
    configured: true,
    getIceServers() {
      issueCount += 1;
      return issueCount === 1 ? firstIssue.promise : closedIssue.promise;
    },
  };
  const server = createSignalingServer({
    codeGenerator: () => (issueCount === 0 ? "ORD234" : "CLS234"),
    iceServerProvider: provider,
  });
  const address = await server.listen(0, "127.0.0.1");
  t.after(async () => server.close());
  const wsUrl = `ws://127.0.0.1:${address.port}`;

  const host = await connect(wsUrl);
  const orderedMessages = nextMessages(host, 2);
  send(host, { type: "host_room" });
  send(host, { type: "host_room" });
  await waitForCondition(() => issueCount === 1, "the first credential request");
  assert.equal(issueCount, 1);
  firstIssue.resolve(temporaryIceServers("ordered"));
  const [created, duplicateError] = await orderedMessages;
  assert.equal(created.type, "room_created");
  assert.equal(duplicateError.type, "error");
  assert.equal(duplicateError.error, "host_already_registered");

  const closingHost = await connect(wsUrl);
  send(closingHost, { type: "host_room" });
  await waitForCondition(() => issueCount === 2, "the closed socket credential request");
  assert.equal(issueCount, 2);
  closingHost.close();
  await new Promise((resolve) => closingHost.once("close", resolve));
  closedIssue.resolve(temporaryIceServers("closed"));
  await new Promise((resolve) => setImmediate(resolve));

  const health = await get(`http://127.0.0.1:${address.port}/health`);
  assert.equal(health.status, 200);
  assert.equal(JSON.parse(health.body).ok, true);
});
