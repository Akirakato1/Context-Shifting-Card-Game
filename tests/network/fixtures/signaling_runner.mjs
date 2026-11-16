import fs from "node:fs";
import path from "node:path";

import { createSignalingServer } from "../../../service/signaling/src/server.js";

function argument(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : "";
}

const outputDir = argument("--output-dir");
const stopFile = argument("--stop-file");
const exitMarker = argument("--exit-marker");
if (!outputDir || !stopFile || !exitMarker) {
  console.error("signaling_runner requires --output-dir, --stop-file, and --exit-marker");
  process.exit(2);
}

function writeStatus(value) {
  fs.writeFileSync(path.join(outputDir, "signaling.json"), JSON.stringify(value));
}

const server = createSignalingServer({ hostReconnectGraceMs: 30_000 });
let nextSocketId = 1;
server.wsServer.on("connection", (socket) => {
  const socketId = nextSocketId++;
  console.log(`SIGNALING_SOCKET_OPEN id=${socketId}`);
  socket.on("message", (raw) => {
    try {
      const message = JSON.parse(raw.toString("utf8"));
      console.log(`SIGNALING_MESSAGE id=${socketId} type=${message.type}`);
    } catch {
      console.log(`SIGNALING_MESSAGE id=${socketId} type=malformed`);
    }
  });
  socket.on("close", (code, reason) => {
    console.log(`SIGNALING_SOCKET_CLOSE id=${socketId} code=${code} reason=${reason}`);
  });
});
const address = await server.listen(0, "127.0.0.1");
const url = `ws://127.0.0.1:${address.port}`;
writeStatus({ state: "ready", url });
console.log(`SIGNALING_READY ${url}`);

let stopping = false;
async function stop(exitCode = 0) {
  if (stopping) return;
  stopping = true;
  clearInterval(stopPoll);
  await server.close();
  writeStatus({ state: "stopped", url });
  fs.writeFileSync(exitMarker, String(exitCode));
  console.log("SIGNALING_STOPPED");
  process.exit(exitCode);
}

const stopPoll = setInterval(() => {
  if (fs.existsSync(stopFile)) {
    stop().catch((error) => {
      console.error(error);
      process.exit(1);
    });
  }
}, 50);

process.on("SIGINT", () => stop(0));
process.on("SIGTERM", () => stop(0));
process.on("uncaughtException", (error) => {
  console.error(error);
  stop(1).catch(() => process.exit(1));
});

