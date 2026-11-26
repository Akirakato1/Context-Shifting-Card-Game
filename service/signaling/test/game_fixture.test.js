import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const fixtureUrl = new URL("./fixtures/game_envelopes.json", import.meta.url);
const kinds = [
  "command",
  "command_result",
  "event_batch",
  "snapshot",
  "view_update",
  "heartbeat",
  "heartbeat_ack",
  "disconnect_notice",
];

test("game envelope fixtures are standard JSON with the complete v1 kind set", async () => {
  const source = await readFile(fixtureUrl, "utf8");
  const fixture = JSON.parse(source);

  assert.equal(fixture.version, 1);
  assert.deepEqual(
    fixture.envelopes.map((envelope) => envelope.kind),
    kinds,
  );
  assert.equal(fixture.envelopes[0].payload.display_name, "Zoë 雪");
  assert.deepEqual(JSON.parse(JSON.stringify(fixture)), fixture);

  for (const envelope of fixture.envelopes) {
    assert.deepEqual(Object.keys(envelope), [
      "v",
      "kind",
      "message_id",
      "match_id",
      "sender_id",
      "payload",
    ]);
    assert.equal(typeof envelope.payload, "object");
    assert.equal(Array.isArray(envelope.payload), false);
  }
});
