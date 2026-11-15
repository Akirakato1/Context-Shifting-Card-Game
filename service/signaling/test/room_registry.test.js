import assert from "node:assert/strict";
import test from "node:test";

import {
  ACTIVE_ROLE,
  SPECTATOR_ROLE,
  RoomRegistry,
  RoomRegistryError,
} from "../src/room_registry.js";

class FakeSocket {
  constructor(id) {
    this.id = id;
    this.readyState = 1;
    this.sent = [];
  }

  send(payload) {
    this.sent.push(payload);
  }
}

function registryFixture() {
  let token = 0;
  let code = 0;
  let now = 1000;
  return {
    registry: new RoomRegistry({
      codeGenerator: () => `ABC${String(code++).padStart(3, "2")}`,
      tokenGenerator: () => `opaque-token-${++token}`,
      now: () => now,
    }),
    advance: (milliseconds) => {
      now += milliseconds;
    },
  };
}

test("generated room codes are six unambiguous uppercase characters", () => {
  const registry = new RoomRegistry();
  const seen = new Set();
  for (let index = 0; index < 64; index += 1) {
    const { code } = registry.createHost(new FakeSocket(`host-${index}`));
    assert.match(code, /^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$/);
    assert.equal(seen.has(code), false);
    seen.add(code);
  }
});

test("room lookup is case-insensitive and host approval gates routing", () => {
  const { registry } = registryFixture();
  const host = new FakeSocket("host");
  const joiner = new FakeSocket("joiner");
  const { code, hostToken } = registry.createHost(host);
  const { joinNonce, peerId } = registry.requestJoin(code.toLowerCase(), ACTIVE_ROLE, joiner);

  assert.equal(registry.canRoute(joiner, code, joinNonce), false);
  assert.equal(registry.approveJoin(code, hostToken, joinNonce).peerId, peerId);
  assert.equal(registry.canRoute(joiner, code.toLowerCase(), joinNonce), true);
  assert.equal(registry.canRoute(joiner, code, "wrong-nonce"), false);
});

test("host counts toward four active seats and pending joins reserve capacity", () => {
  const { registry } = registryFixture();
  const { code } = registry.createHost(new FakeSocket("host"));

  for (let index = 0; index < 3; index += 1) {
    registry.requestJoin(code, ACTIVE_ROLE, new FakeSocket(`active-${index}`));
  }
  assert.throws(
    () => registry.requestJoin(code, ACTIVE_ROLE, new FakeSocket("active-full")),
    (error) => error instanceof RoomRegistryError && error.code === "active_capacity_reached",
  );
});

test("four pending spectators reserve all spectator capacity", () => {
  const { registry } = registryFixture();
  const { code } = registry.createHost(new FakeSocket("host"));

  for (let index = 0; index < 4; index += 1) {
    registry.requestJoin(code, SPECTATOR_ROLE, new FakeSocket(`spectator-${index}`));
  }
  assert.throws(
    () => registry.requestJoin(code, SPECTATOR_ROLE, new FakeSocket("spectator-full")),
    (error) => error instanceof RoomRegistryError && error.code === "spectator_capacity_reached",
  );
});

test("host close invalidates the code and returns every pending socket", () => {
  const { registry } = registryFixture();
  const host = new FakeSocket("host");
  const active = new FakeSocket("active");
  const spectator = new FakeSocket("spectator");
  const { code } = registry.createHost(host);
  registry.requestJoin(code, ACTIVE_ROLE, active);
  registry.requestJoin(code, SPECTATOR_ROLE, spectator);

  const closed = registry.closeHost(host);

  assert.deepEqual(new Set(closed.peerSockets), new Set([active, spectator]));
  assert.equal(registry.inspectRoom(code), null);
  assert.throws(
    () => registry.requestJoin(code, ACTIVE_ROLE, new FakeSocket("late")),
    (error) => error instanceof RoomRegistryError && error.code === "room_not_found",
  );
});

test("room records contain signaling metadata and no canonical game state", () => {
  const { registry, advance } = registryFixture();
  const host = new FakeSocket("host");
  const { code } = registry.createHost(host);
  advance(25);
  registry.requestJoin(code, ACTIVE_ROLE, new FakeSocket("active"));
  const room = registry.inspectRoom(code);

  assert.deepEqual(Object.keys(room).sort(), [
    "code",
    "createdAt",
    "hostSocket",
    "hostToken",
    "joins",
    "lastActivityAt",
  ]);
  const serializedKeys = JSON.stringify(room, (key, value) =>
    key.endsWith("Socket") ? `[socket:${value.id}]` : value,
  );
  for (const forbidden of ["cards", "hands", "scores", "matchState", "rng", "abilityDeck"]) {
    assert.equal(serializedKeys.includes(forbidden), false);
  }
});
