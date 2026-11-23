import { randomBytes, randomInt } from "node:crypto";

export const ACTIVE_ROLE = "active";
export const SPECTATOR_ROLE = "spectator";

const CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
const CODE_LENGTH = 6;
const ACTIVE_CAPACITY = 4;
const SPECTATOR_CAPACITY = 4;

export class RoomRegistryError extends Error {
  constructor(code) {
    super(code);
    this.name = "RoomRegistryError";
    this.code = code;
  }
}

function defaultCodeGenerator() {
  let code = "";
  for (let index = 0; index < CODE_LENGTH; index += 1) {
    code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  }
  return code;
}

function defaultTokenGenerator() {
  return randomBytes(32).toString("hex");
}

function normalizeCode(code) {
  return String(code).toUpperCase();
}

export class RoomRegistry {
  constructor({
    codeGenerator = defaultCodeGenerator,
    tokenGenerator = defaultTokenGenerator,
    now = Date.now,
    hostReconnectGraceMs = 30_000,
    onRoomChanged = null,
    onDetachedHostExpired = null,
  } = {}) {
    this.codeGenerator = codeGenerator;
    this.tokenGenerator = tokenGenerator;
    this.now = now;
    this.hostReconnectGraceMs = hostReconnectGraceMs;
    this.onRoomChanged = onRoomChanged;
    this.onDetachedHostExpired = onDetachedHostExpired;
    this.rooms = new Map();
    this.hostRooms = new WeakMap();
    this.socketJoins = new WeakMap();
  }

  restoreRoom(room) {
    this.rooms.set(room.code, room);
    if (room.hostSocket) {
      this.hostRooms.set(room.hostSocket, room.code);
    }
    for (const [joinNonce, join] of room.joins) {
      this.socketJoins.set(join.socket, { code: room.code, joinNonce });
    }
  }

  createHost(socket) {
    if (this.hostRooms.has(socket)) {
      throw new RoomRegistryError("host_already_registered");
    }
    let code;
    for (let attempt = 0; attempt < 128; attempt += 1) {
      const candidate = normalizeCode(this.codeGenerator());
      if (candidate.length === CODE_LENGTH && !this.rooms.has(candidate)) {
        code = candidate;
        break;
      }
    }
    if (!code) {
      throw new RoomRegistryError("room_code_exhausted");
    }
    const timestamp = this.now();
    const room = {
      code,
      hostSocket: socket,
      hostDetachedAt: null,
      hostToken: this.tokenGenerator(),
      joins: new Map(),
      createdAt: timestamp,
      lastActivityAt: timestamp,
    };
    this.rooms.set(code, room);
    this.hostRooms.set(socket, code);
    this.onRoomChanged?.(code, room);
    return { code, hostToken: room.hostToken };
  }

  requestJoin(code, role, socket, displayName = "Player", reconnectPlayerId = "") {
    const room = this.#requireRoom(code);
    if (room.hostSocket === null) {
      throw new RoomRegistryError("host_temporarily_unavailable");
    }
    if (role !== ACTIVE_ROLE && role !== SPECTATOR_ROLE) {
      throw new RoomRegistryError("invalid_role");
    }
    if (this.socketJoins.has(socket)) {
      throw new RoomRegistryError("join_already_pending");
    }
    let roleCount = role === ACTIVE_ROLE ? 1 : 0;
    for (const join of room.joins.values()) {
      if (join.role === role) {
        roleCount += 1;
      }
    }
    const capacity = role === ACTIVE_ROLE ? ACTIVE_CAPACITY : SPECTATOR_CAPACITY;
    if (roleCount >= capacity) {
      throw new RoomRegistryError(
        role === ACTIVE_ROLE ? "active_capacity_reached" : "spectator_capacity_reached",
      );
    }

    const joinNonce = this.tokenGenerator();
    const peerId = this.tokenGenerator();
    const timestamp = this.now();
    const join = {
      socket,
      role,
      joinNonce,
      peerId,
      displayName,
      reconnectPlayerId,
      approved: false,
      createdAt: timestamp,
      lastActivityAt: timestamp,
    };
    room.joins.set(joinNonce, join);
    room.lastActivityAt = timestamp;
    this.socketJoins.set(socket, { code: room.code, joinNonce });
    this.onRoomChanged?.(room.code, room);
    return { joinNonce, peerId };
  }

  approveJoin(code, hostToken, joinNonce) {
    const room = this.#requireHostToken(code, hostToken);
    const join = room.joins.get(joinNonce);
    if (!join) {
      throw new RoomRegistryError("invalid_join_nonce");
    }
    join.approved = true;
    join.lastActivityAt = this.now();
    room.lastActivityAt = join.lastActivityAt;
    this.onRoomChanged?.(room.code, room);
    return {
      peerId: join.peerId, socket: join.socket, role: join.role,
      displayName: join.displayName,
      reconnectPlayerId: join.reconnectPlayerId,
    };
  }

  joinRouteStatus(socket, code, joinNonce) {
    const room = this.rooms.get(normalizeCode(code));
    if (!room) {
      return { ok: false, error: "room_not_found" };
    }
    const join = room.joins.get(joinNonce);
    if (!join || join.socket !== socket) {
      return { ok: false, error: "invalid_join_nonce" };
    }
    if (!join.approved) {
      return { ok: false, error: "join_not_approved" };
    }
    join.lastActivityAt = this.now();
    room.lastActivityAt = join.lastActivityAt;
    return { ok: true, room, join };
  }

  canRoute(socket, code, joinNonce) {
    return this.joinRouteStatus(socket, code, joinNonce).ok;
  }

  hostRoute(code, hostToken, peerId) {
    const room = this.#requireHostToken(code, hostToken);
    for (const join of room.joins.values()) {
      if (join.peerId === peerId && join.approved) {
        return { room, join };
      }
    }
    throw new RoomRegistryError("unknown_peer");
  }

  isHost(socket, code, hostToken) {
    const room = this.rooms.get(normalizeCode(code));
    return room?.hostSocket === socket && room.hostToken === hostToken;
  }

  closeHost(socket) {
    const code = this.hostRooms.get(socket);
    if (!code) {
      throw new RoomRegistryError("host_authorization_required");
    }
    const room = this.rooms.get(code);
    this.rooms.delete(code);
    this.hostRooms.delete(socket);
    const peerSockets = [];
    for (const join of room.joins.values()) {
      peerSockets.push(join.socket);
      this.socketJoins.delete(join.socket);
    }
    this.onRoomChanged?.(code, null);
    return { code, peerSockets };
  }

  reconnectHost(socket, code, hostToken) {
    if (this.hostRooms.has(socket)) {
      throw new RoomRegistryError("host_already_registered");
    }
    const room = this.#requireRoom(code);
    if (room.hostToken !== hostToken) {
      throw new RoomRegistryError("host_authorization_required");
    }
    if (room.hostSocket !== null) {
      throw new RoomRegistryError("host_already_registered");
    }
    room.hostSocket = socket;
    room.hostDetachedAt = null;
    room.lastActivityAt = this.now();
    this.hostRooms.set(socket, room.code);
    this.onRoomChanged?.(room.code, room);
    return { code: room.code };
  }

  expireDetachedHost(code, hostToken) {
    const room = this.rooms.get(normalizeCode(code));
    if (!room || room.hostToken !== hostToken || room.hostSocket !== null) {
      return null;
    }
    if (this.now() - room.hostDetachedAt < this.hostReconnectGraceMs) {
      return null;
    }
    this.rooms.delete(room.code);
    const peerSockets = [];
    for (const join of room.joins.values()) {
      peerSockets.push(join.socket);
      this.socketJoins.delete(join.socket);
    }
    this.onRoomChanged?.(room.code, null);
    const result = { code: room.code, peerSockets };
    this.onDetachedHostExpired?.(result);
    return result;
  }

  removeSocket(socket) {
    if (this.hostRooms.has(socket)) {
      const code = this.hostRooms.get(socket);
      const room = this.rooms.get(code);
      this.hostRooms.delete(socket);
      if (!room) {
        return { hostClosed: false, hostDetached: false };
      }
      room.hostSocket = null;
      room.hostDetachedAt = this.now();
      room.lastActivityAt = room.hostDetachedAt;
      this.onRoomChanged?.(code, room);
      return {
        hostClosed: false,
        hostDetached: true,
        code,
        hostToken: room.hostToken,
      };
    }
    const reference = this.socketJoins.get(socket);
    if (!reference) {
      return { hostClosed: false };
    }
    const room = this.rooms.get(reference.code);
    room?.joins.delete(reference.joinNonce);
    if (room) {
      room.lastActivityAt = this.now();
      this.onRoomChanged?.(room.code, room);
    }
    this.socketJoins.delete(socket);
    return { hostClosed: false };
  }

  inspectRoom(code) {
    const normalized = normalizeCode(code);
    const room = this.rooms.get(normalized);
    if (
      room?.hostSocket === null
      && this.now() - room.hostDetachedAt >= this.hostReconnectGraceMs
    ) {
      this.expireDetachedHost(normalized, room.hostToken);
      return null;
    }
    return room ?? null;
  }

  #requireRoom(code) {
    const room = this.inspectRoom(code);
    if (!room) {
      throw new RoomRegistryError("room_not_found");
    }
    return room;
  }

  #requireHostToken(code, hostToken) {
    const room = this.#requireRoom(code);
    if (room.hostToken !== hostToken) {
      throw new RoomRegistryError("host_authorization_required");
    }
    return room;
  }
}
