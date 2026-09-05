// Worker half of provider-cooldown.int.test.ts: adopts the cooldown buffer the
// main thread passed via workerData, then answers "is <provider> cooling down?"
// — the SAME question the monitor cycle's fetchers ask on this thread.
import { register } from "tsx/esm/api";
import { parentPort, workerData } from "node:worker_threads";

register();
const { attachCooldownState, rateLimitedUntil, noteRateLimited } = await import("@agentic-toolkit/deploy-platform/cooldown");

attachCooldownState(workerData.cooldowns);

parentPort.on("message", (msg) => {
  if (msg.op === "read") {
    parentPort.postMessage({ until: rateLimitedUntil(msg.provider) });
  } else if (msg.op === "note") {
    noteRateLimited(msg.provider, msg.retryAfter ?? null);
    parentPort.postMessage({ noted: true });
  }
});
