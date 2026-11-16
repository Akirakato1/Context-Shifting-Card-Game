export const PROTOCOL_VERSION = 1;
export const MAX_MESSAGE_BYTES = 64 * 1024;

export const CLIENT_MESSAGE_TYPES = new Set([
  "host_room",
  "join_room",
  "approve_join",
  "offer",
  "answer",
  "ice_candidate",
  "close_room",
]);

const SIGNAL_TYPES = new Set(["offer", "answer", "ice_candidate"]);
const VALID_ROLES = new Set(["active", "spectator"]);

function failure(error) {
  return { ok: false, error };
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.length > 0;
}

export function decodeClientMessage(raw) {
  const bytes = Buffer.isBuffer(raw) ? raw : Buffer.from(raw);
  if (bytes.byteLength > MAX_MESSAGE_BYTES) {
    return failure("message_too_large");
  }

  let message;
  try {
    message = JSON.parse(bytes.toString("utf8"));
  } catch {
    return failure("malformed_json");
  }
  if (message === null || Array.isArray(message) || typeof message !== "object") {
    return failure("malformed_message");
  }
  if (message.v !== PROTOCOL_VERSION) {
    return failure("unsupported_version");
  }
  if (!CLIENT_MESSAGE_TYPES.has(message.type)) {
    return failure("unknown_message_type");
  }

  if (message.type === "host_room") {
    if (message.reconnect === true && (
      !isNonEmptyString(message.code) || !isNonEmptyString(message.host_token)
    )) {
      return failure("malformed_message");
    }
  } else if (message.type === "join_room") {
    if (!isNonEmptyString(message.code)) {
      return failure("invalid_room_code");
    }
    if (!VALID_ROLES.has(message.role)) {
      return failure("invalid_role");
    }
    if (
      !isNonEmptyString(message.display_name)
      || message.display_name.trim().length === 0
      || message.display_name.length > 32
    ) {
      return failure("invalid_display_name");
    }
  } else if (message.type === "approve_join") {
    if (
      !isNonEmptyString(message.code)
      || !isNonEmptyString(message.host_token)
      || !isNonEmptyString(message.join_nonce)
    ) {
      return failure("malformed_message");
    }
  } else if (SIGNAL_TYPES.has(message.type)) {
    if (!isNonEmptyString(message.code) || message.payload === null || typeof message.payload !== "object") {
      return failure("malformed_message");
    }
    const hasJoinCredentials = isNonEmptyString(message.join_nonce);
    const hasHostCredentials = isNonEmptyString(message.host_token) && isNonEmptyString(message.peer_id);
    if (!hasJoinCredentials && !hasHostCredentials) {
      return failure("missing_route_credentials");
    }
  } else if (message.type === "close_room") {
    if (!isNonEmptyString(message.code)) {
      return failure("invalid_room_code");
    }
  }

  return { ok: true, message };
}

export class MessageRateLimiter {
  constructor({ limit = 120, windowMs = 10_000, now = Date.now } = {}) {
    this.limit = limit;
    this.windowMs = windowMs;
    this.now = now;
    this.windows = new WeakMap();
  }

  accept(socket) {
    const timestamp = this.now();
    let window = this.windows.get(socket);
    if (!window || timestamp - window.startedAt >= this.windowMs) {
      window = { startedAt: timestamp, count: 0 };
      this.windows.set(socket, window);
    }
    if (window.count >= this.limit) {
      return false;
    }
    window.count += 1;
    return true;
  }
}

export function serverMessage(type, fields = {}) {
  return JSON.stringify({ v: PROTOCOL_VERSION, type, ...fields });
}
