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
  } = {}) {
    this.codeGenerator = codeGenerator;
    this.tokenGenerator = tokenGenerator;
    this.now = now;
    this.rooms = new Map();
    this.hostRooms = new WeakMap();
    this.socketJoins = new WeakMap();
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
      hostToken: this.tokenGenerator(),
      joins: new Map(),
      createdAt: timestamp,
      lastActivityAt: timestamp,
    };
    this.rooms.set(code, room);
    this.hostRooms.set(socket, code);
    return { code, hostToken: room.hostToken };
  }

  requestJoin(code, role, socket) {
    const room = this.#requireRoom(code);
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
      approved: false,
      createdAt: timestamp,
      lastActivityAt: timestamp,
    };
    room.joins.set(joinNonce, join);
    room.lastActivityAt = timestamp;
    this.socketJoins.set(socket, { code: room.code, joinNonce });
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
    return { peerId: join.peerId, socket: join.socket, role: join.role };
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
    return { code, peerSockets };
  }

  removeSocket(socket) {
    if (this.hostRooms.has(socket)) {
      return { hostClosed: true, ...this.closeHost(socket) };
    }
    const reference = this.socketJoins.get(socket);
    if (!reference) {
      return { hostClosed: false };
    }
    const room = this.rooms.get(reference.code);
    room?.joins.delete(reference.joinNonce);
    if (room) {
      room.lastActivityAt = this.now();
    }
    this.socketJoins.delete(socket);
    return { hostClosed: false };
  }

  inspectRoom(code) {
    return this.rooms.get(normalizeCode(code)) ?? null;
  }

  #requireRoom(code) {
    const room = this.rooms.get(normalizeCode(code));
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
