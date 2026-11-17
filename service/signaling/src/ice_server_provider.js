const DEFAULT_TTL_SECONDS = 14_400;
const MIN_TTL_SECONDS = 60;
const MAX_TTL_SECONDS = 172_800;
const MAX_ICE_SERVERS = 8;
const MAX_URLS_PER_SERVER = 8;
const MAX_URL_LENGTH = 2_048;
const MAX_CREDENTIAL_LENGTH = 1_024;
const FALLBACK_ICE_SERVERS = [
  { urls: ["stun:stun.l.google.com:19302"] },
];

function invalidIceServers() {
  return new TypeError("Invalid ICE server configuration");
}

function boundedString(value, maximumLength) {
  return typeof value === "string" && value.length > 0 && value.length <= maximumLength;
}

function normalizeTtl(value) {
  const parsed = Number.parseInt(value ?? "", 10);
  if (!Number.isFinite(parsed)) {
    return DEFAULT_TTL_SECONDS;
  }
  return Math.min(MAX_TTL_SECONDS, Math.max(MIN_TTL_SECONDS, parsed));
}

export function fallbackIceServers() {
  return structuredClone(FALLBACK_ICE_SERVERS);
}

export function normalizeIceServers(value) {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_ICE_SERVERS) {
    throw invalidIceServers();
  }

  return value.map((entry) => {
    if (entry === null || Array.isArray(entry) || typeof entry !== "object") {
      throw invalidIceServers();
    }
    const sourceUrls = typeof entry.urls === "string" ? [entry.urls] : entry.urls;
    if (
      !Array.isArray(sourceUrls)
      || sourceUrls.length === 0
      || sourceUrls.length > MAX_URLS_PER_SERVER
    ) {
      throw invalidIceServers();
    }
    const urls = sourceUrls.map((url) => {
      if (
        !boundedString(url, MAX_URL_LENGTH)
        || !/^(?:stun|stuns|turn|turns):/i.test(url)
      ) {
        throw invalidIceServers();
      }
      return url;
    });

    const hasUsername = Object.hasOwn(entry, "username");
    const hasCredential = Object.hasOwn(entry, "credential");
    if (hasUsername !== hasCredential) {
      throw invalidIceServers();
    }

    const normalized = { urls };
    if (hasUsername) {
      if (
        !boundedString(entry.username, MAX_CREDENTIAL_LENGTH)
        || !boundedString(entry.credential, MAX_CREDENTIAL_LENGTH)
      ) {
        throw invalidIceServers();
      }
      normalized.username = entry.username;
      normalized.credential = entry.credential;
    }
    return normalized;
  });
}

export function createIceServerProvider({
  env = process.env,
  fetchImpl = globalThis.fetch,
  requestTimeoutMs = 5_000,
} = {}) {
  const keyId = typeof env.CLOUDFLARE_TURN_KEY_ID === "string"
    ? env.CLOUDFLARE_TURN_KEY_ID.trim()
    : "";
  const apiToken = typeof env.CLOUDFLARE_TURN_API_TOKEN === "string"
    ? env.CLOUDFLARE_TURN_API_TOKEN.trim()
    : "";
  if (!keyId || !apiToken) {
    return {
      name: "none",
      configured: false,
      async getIceServers() {
        return fallbackIceServers();
      },
    };
  }

  const ttl = normalizeTtl(env.TURN_CREDENTIAL_TTL_SECONDS);
  const timeout = Math.max(1, Number.isFinite(requestTimeoutMs) ? requestTimeoutMs : 5_000);
  const endpoint = `https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(keyId)}/credentials/generate-ice-servers`;

  return {
    name: "cloudflare",
    configured: true,
    async getIceServers() {
      try {
        if (typeof fetchImpl !== "function") {
          throw new TypeError("fetch unavailable");
        }
        const result = await fetchImpl(endpoint, {
          method: "POST",
          headers: {
            authorization: `Bearer ${apiToken}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({ ttl }),
          signal: AbortSignal.timeout(timeout),
        });
        if (!result?.ok) {
          throw new Error("provider rejected request");
        }
        const payload = await result.json();
        const iceServers = normalizeIceServers(payload?.iceServers);
        const hasTurn = iceServers.some((entry) => (
          entry.username !== undefined
          && entry.urls.some((url) => /^(?:turn|turns):/i.test(url))
        ));
        if (!hasTurn) {
          throw invalidIceServers();
        }
        return iceServers;
      } catch {
        throw new Error("Cloudflare TURN credential request failed");
      }
    },
  };
}
