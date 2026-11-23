import assert from "node:assert/strict";
import { once } from "node:events";
import { createRequire } from "node:module";
import { after, before, test } from "node:test";
import { fileURLToPath } from "node:url";
import { WebSocket } from "ws";

// Use the version of Miniflare that backs the pinned Wrangler dependency.
const { Miniflare, convertV4MiniflareOptions } = createRequire(import.meta.resolve("wrangler"))("miniflare");

const WORKER_NAME = "shift-signaling-test";
const HUB_CLASS = "SignalingHub";
const HUB_BINDING = "SIGNALING_HUB";
const ICE_SERVERS = [{ urls: ["stun:stun.l.google.com:19302"] }];
const SOURCE_DIR = new URL("../src/", import.meta.url);
let worker;

before(async () => {
  worker = new Miniflare(convertV4MiniflareOptions({
    name: WORKER_NAME,
    cf: false,
    modulesRoot: fileURLToPath(SOURCE_DIR),
    modules: ["worker.js", "ice_server_provider.js", "protocol.js", "room_registry.js", "signaling_session.js"]
      .map((file) => ({ type: "ESModule", path: fileURLToPath(new URL(file, SOURCE_DIR)) })),
    compatibilityDate: "2026-11-01",
    compatibilityFlags: ["nodejs_compat"],
    durableObjects: {
      [HUB_BINDING]: { className: HUB_CLASS, useSQLite: true },
    },
  }));
  await worker.ready;
});

after(async () => {
  await worker?.dispose();
});

async function connect(t) {
  const url = new URL("/", await worker.ready);
  url.protocol = "ws:";
  const socket = new WebSocket(url);
  t.after(() => socket.terminate());
  await once(socket, "open", { signal: AbortSignal.timeout(5_000) });
  return socket;
}

async function nextMessage(socket) {
  const [raw] = await once(socket, "message", { signal: AbortSignal.timeout(5_000) });
  const message = JSON.parse(raw.toString("utf8"));
  assert.equal(message.v, 1);
  return message;
}

function send(socket, message) {
  socket.send(JSON.stringify({ v: 1, ...message }));
}

function replyTo(socket, message) {
  const reply = nextMessage(socket);
  send(socket, message);
  return reply;
}

async function hostRoom(t) {
  const host = await connect(t);
  const created = await replyTo(host, { type: "host_room" });
  assert.equal(created.type, "room_created");
  assert.match(created.code, /^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$/);
  assert.ok(created.host_token);
  assert.equal(created.relay_available, false);
  assert.deepEqual(created.ice_servers, ICE_SERVERS);
  return { host, code: created.code, host_token: created.host_token };
}

async function requestJoin(t, { host, code }) {
  const guest = await connect(t);
  const request = nextMessage(host);
  const pending = replyTo(guest, {
    type: "join_room",
    code: code.toLowerCase(),
    role: "spectator",
    display_name: "Mira",
    reconnect_player_id: "player-2",
  });
  const [requested, joined] = await Promise.all([request, pending]);
  assert.equal(joined.type, "join_pending");
  assert.ok(joined.join_nonce);
  assert.ok(joined.peer_id);
  assert.deepEqual(joined, {
    v: 1,
    type: "join_pending",
    code,
    role: "spectator",
    display_name: "Mira",
    reconnect_player_id: "player-2",
    join_nonce: joined.join_nonce,
    peer_id: joined.peer_id,
  });
  assert.deepEqual(requested, { ...joined, type: "join_requested" });
  return { guest, joined };
}

async function approveJoin({ host, code, host_token }, { guest, joined }) {
  const approval = nextMessage(guest);
  send(host, { type: "approve_join", code, host_token, join_nonce: joined.join_nonce });
  assert.deepEqual(await approval, {
    ...joined,
    type: "join_approved",
    ice_servers: ICE_SERVERS,
    relay_available: false,
  });
}

test("Worker health reports the signaling protocol and relay status", async () => {
  const health = await worker.dispatchFetch("http://localhost/health");
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), {
    ok: true,
    service: "shift-signaling",
    v: 1,
    relay: { provider: "none", configured: false },
  });
});

test("Worker routes WebRTC messages only after host approval", async (t) => {
  const room = await hostRoom(t);
  const { host, code, host_token } = room;
  const join = await requestJoin(t, room);
  const { guest, joined: { join_nonce, peer_id } } = join;
  const offer = { type: "offer", code, join_nonce, payload: { sdp: "guest-offer" } };

  assert.deepEqual(await replyTo(guest, offer), {
    v: 1, type: "error", error: "join_not_approved",
  });
  await approveJoin(room, join);

  const forwardedOffer = nextMessage(host);
  send(guest, offer);
  assert.deepEqual(await forwardedOffer, {
    v: 1, type: "offer", code, peer_id, payload: { sdp: "guest-offer" },
  });

  const forwardedAnswer = nextMessage(guest);
  send(host, { type: "answer", code, host_token, peer_id, payload: { sdp: "host-answer" } });
  assert.deepEqual(await forwardedAnswer, {
    v: 1, type: "answer", code, peer_id, payload: { sdp: "host-answer" },
  });
});

test("Worker restores approved WebSocket routes after Durable Object hibernation", async (t) => {
  const room = await hostRoom(t);
  const join = await requestJoin(t, room);
  await approveJoin(room, join);

  const ids = await worker.listDurableObjectIds(HUB_BINDING);
  assert.ok(ids.length > 0);
  for (const id of ids) {
    await worker.unsafeEvictDurableObject(WORKER_NAME, HUB_CLASS, { id, webSockets: "hibernate" });
  }

  const { host, code } = room;
  const { guest, joined: { peer_id, join_nonce } } = join;
  const payload = { candidate: "candidate-after-hibernation", sdp_mid: "0", sdp_mline_index: 0 };
  const forwarded = nextMessage(host);
  send(guest, { type: "ice_candidate", code, join_nonce, payload });
  assert.deepEqual(await forwarded, { v: 1, type: "ice_candidate", code, peer_id, payload });
});

test("Worker lets the authorized host resume a disconnected room", async (t) => {
  const room = await hostRoom(t);
  const { host, code, host_token } = room;
  const join = await requestJoin(t, room);
  await approveJoin(room, join);

  const hostClosed = once(host, "close", { signal: AbortSignal.timeout(5_000) }).catch((cause) => {
    throw new Error("Host WebSocket close handshake did not complete", { cause });
  });
  host.close(1000);
  const [closeCode] = await hostClosed;
  assert.equal(closeCode, 1000);

  const replacement = await connect(t);
  assert.deepEqual(await replyTo(replacement, {
    type: "join_room", code, role: "active", display_name: "Mira",
  }), { v: 1, type: "error", error: "host_temporarily_unavailable" });

  const reconnect = { type: "host_room", reconnect: true, code };
  assert.deepEqual(await replyTo(replacement, { ...reconnect, host_token: "incorrect" }), {
    v: 1, type: "error", error: "host_authorization_required",
  });
  assert.deepEqual(await replyTo(replacement, { ...reconnect, host_token }), {
    v: 1, type: "room_created", code, host_token, ice_servers: ICE_SERVERS, relay_available: false,
  });

  const guestClosed = nextMessage(join.guest);
  const roomClosed = replyTo(replacement, { type: "close_room", code, host_token });
  const expected = { v: 1, type: "room_closed", code };
  assert.deepEqual(await Promise.all([guestClosed, roomClosed]), [expected, expected]);
});

test("Worker returns protocol errors without closing a client's WebSocket", async (t) => {
  const socket = await connect(t);
  const malformed = nextMessage(socket);
  socket.send("{");
  assert.deepEqual(await malformed, { v: 1, type: "error", error: "malformed_json" });
  assert.deepEqual(await replyTo(socket, { v: 2, type: "host_room" }), {
    v: 1, type: "error", error: "unsupported_version",
  });
  assert.deepEqual(await replyTo(socket, { type: "game_state" }), {
    v: 1, type: "error", error: "unknown_message_type",
  });
  assert.deepEqual(await replyTo(socket, {
    type: "join_room", code: "missing", role: "active", display_name: "Mira",
  }), { v: 1, type: "error", error: "room_not_found" });
  assert.deepEqual(await replyTo(socket, { type: "close_room", code: "ABC234" }), {
    v: 1, type: "error", error: "host_authorization_required",
  });
  assert.equal((await replyTo(socket, { type: "host_room" })).type, "room_created");
});
