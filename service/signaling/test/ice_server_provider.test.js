import assert from "node:assert/strict";
import test from "node:test";

import {
  createIceServerProvider,
  fallbackIceServers,
  normalizeIceServers,
} from "../src/ice_server_provider.js";

const VALID_CLOUDFLARE_RESPONSE = {
  iceServers: [
    { urls: ["stun:stun.cloudflare.com:3478"] },
    {
      urls: [
        "turn:turn.cloudflare.com:3478?transport=udp",
        "turns:turn.cloudflare.com:5349?transport=tcp",
      ],
      username: "temporary-user",
      credential: "temporary-password",
      ignored: "provider-detail",
    },
  ],
};

function response(body, { ok = true, status = 200 } = {}) {
  return {
    ok,
    status,
    async json() {
      return body;
    },
  };
}

test("unconfigured provider returns the STUN fallback without calling fetch", async () => {
  let fetchCalls = 0;
  const provider = createIceServerProvider({
    env: {},
    fetchImpl: async () => {
      fetchCalls += 1;
      throw new Error("fetch must not be called");
    },
  });

  assert.equal(provider.name, "none");
  assert.equal(provider.configured, false);
  const first = await provider.getIceServers();
  assert.deepEqual(first, [{ urls: ["stun:stun.l.google.com:19302"] }]);
  assert.deepEqual(first, fallbackIceServers());
  first[0].urls[0] = "stun:mutated.invalid";
  assert.deepEqual(await provider.getIceServers(), [
    { urls: ["stun:stun.l.google.com:19302"] },
  ]);
  assert.equal(fetchCalls, 0);
});

test("cloudflare provider posts bounded TTL and normalizes its ICE response", async () => {
  const requests = [];
  const provider = createIceServerProvider({
    env: {
      CLOUDFLARE_TURN_KEY_ID: "key/id",
      CLOUDFLARE_TURN_API_TOKEN: "permanent-secret",
      TURN_CREDENTIAL_TTL_SECONDS: "14400",
    },
    fetchImpl: async (url, options) => {
      requests.push({ url, options });
      return response(VALID_CLOUDFLARE_RESPONSE);
    },
  });

  assert.equal(provider.name, "cloudflare");
  assert.equal(provider.configured, true);
  assert.deepEqual(await provider.getIceServers(), [
    { urls: ["stun:stun.cloudflare.com:3478"] },
    {
      urls: [
        "turn:turn.cloudflare.com:3478?transport=udp",
        "turns:turn.cloudflare.com:5349?transport=tcp",
      ],
      username: "temporary-user",
      credential: "temporary-password",
    },
  ]);
  assert.equal(requests.length, 1);
  assert.equal(
    requests[0].url,
    "https://rtc.live.cloudflare.com/v1/turn/keys/key%2Fid/credentials/generate-ice-servers",
  );
  assert.equal(requests[0].options.method, "POST");
  assert.deepEqual(requests[0].options.headers, {
    authorization: "Bearer permanent-secret",
    "content-type": "application/json",
  });
  assert.deepEqual(JSON.parse(requests[0].options.body), { ttl: 14400 });
  assert.ok(requests[0].options.signal instanceof AbortSignal);
});

test("cloudflare provider clamps TTL to the supported range", async () => {
  const observedTtls = [];
  const fetchImpl = async (_url, options) => {
    observedTtls.push(JSON.parse(options.body).ttl);
    return response(VALID_CLOUDFLARE_RESPONSE);
  };
  const shared = {
    CLOUDFLARE_TURN_KEY_ID: "key-id",
    CLOUDFLARE_TURN_API_TOKEN: "token",
  };

  await createIceServerProvider({
    env: { ...shared, TURN_CREDENTIAL_TTL_SECONDS: "1" },
    fetchImpl,
  }).getIceServers();
  await createIceServerProvider({
    env: { ...shared, TURN_CREDENTIAL_TTL_SECONDS: "999999" },
    fetchImpl,
  }).getIceServers();
  await createIceServerProvider({
    env: { ...shared, TURN_CREDENTIAL_TTL_SECONDS: "not-a-number" },
    fetchImpl,
  }).getIceServers();

  assert.deepEqual(observedTtls, [60, 172800, 14400]);
});

test("cloudflare provider rejects HTTP and malformed responses without exposing secrets", async () => {
  const env = {
    CLOUDFLARE_TURN_KEY_ID: "private-key-id",
    CLOUDFLARE_TURN_API_TOKEN: "private-api-token",
  };
  const failing = createIceServerProvider({
    env,
    fetchImpl: async () => response({}, { ok: false, status: 401 }),
  });
  const malformed = createIceServerProvider({
    env,
    fetchImpl: async () => response({
      iceServers: [{ urls: ["stun:stun.cloudflare.com:3478"] }],
    }),
  });

  for (const provider of [failing, malformed]) {
    await assert.rejects(provider.getIceServers(), (error) => {
      assert.match(error.message, /Cloudflare TURN credential request failed/);
      assert.doesNotMatch(error.message, /private-key-id|private-api-token/);
      return true;
    });
  }
});

test("normalization rejects oversized URL collections and unpaired credentials", () => {
  assert.throws(
    () => normalizeIceServers([{ urls: Array.from({ length: 9 }, (_, index) => `stun:${index}`) }]),
    /Invalid ICE server configuration/,
  );
  assert.throws(
    () => normalizeIceServers([{ urls: ["turn:relay.example"], username: "only-user" }]),
    /Invalid ICE server configuration/,
  );
  assert.throws(
    () => normalizeIceServers([{ urls: ["x".repeat(2049)] }]),
    /Invalid ICE server configuration/,
  );
  assert.throws(
    () => normalizeIceServers(Array.from({ length: 9 }, () => ({ urls: ["stun:one"] }))),
    /Invalid ICE server configuration/,
  );
});

test("cloudflare request carries a five-second abort signal", async (t) => {
  const originalTimeout = AbortSignal.timeout;
  let observedTimeout = 0;
  AbortSignal.timeout = (milliseconds) => {
    observedTimeout = milliseconds;
    return new AbortController().signal;
  };
  t.after(() => {
    AbortSignal.timeout = originalTimeout;
  });

  const provider = createIceServerProvider({
    env: {
      CLOUDFLARE_TURN_KEY_ID: "key-id",
      CLOUDFLARE_TURN_API_TOKEN: "token",
    },
    fetchImpl: async () => response(VALID_CLOUDFLARE_RESPONSE),
  });
  await provider.getIceServers();

  assert.equal(observedTimeout, 5000);
});
