// Spawns the monitor worker via its resolved package entry under BARE node — no tsx
// CLI, no loader flags in execArgv — the exact conditions of the prod worker thread
// that crash-looped lewis. Run by worker-boot.int.test.ts as a child process; prints
// REPLY:<json> on a completed cycle round-trip, exits non-zero on worker error.
//
// The workerData JSON arrives on STDIN, not argv: it carries the resolved config —
// `config.secrets` is the whole process env — and a command-line argument is world-
// readable through `ps` for the life of the process, and would be echoed back into
// any error the test throws. Stdin is neither.
import { Worker } from "node:worker_threads";

const [entry] = process.argv.slice(2);
if (!entry) {
  console.error("usage: node worker-boot-driver.mjs <resolved-worker-entry>  < workerData-json");
  process.exit(2);
}

let workerDataJson = "";
for await (const chunk of process.stdin) workerDataJson += chunk;
if (!workerDataJson.trim()) {
  console.error("usage: workerData JSON expected on stdin");
  process.exit(2);
}

const timer = setTimeout(() => {
  console.error("TIMEOUT: no cycle reply within 30s");
  process.exit(3);
}, 30_000);

const worker = new Worker(entry, { workerData: JSON.parse(workerDataJson) });
worker.on("error", (err) => {
  console.error(`WORKER ERROR: ${err instanceof Error ? err.message : String(err)}`);
  process.exit(1);
});
worker.on("message", (msg) => {
  clearTimeout(timer);
  console.log(`REPLY:${JSON.stringify(msg)}`);
  void worker.terminate().then(() => process.exit(0));
});
// Same fire-immediately contract as MonitorWorkerClient.runCycle: the port queues
// the message until worker.ts attaches its listener after module evaluation.
worker.postMessage({ seq: 1, fullSync: false });
