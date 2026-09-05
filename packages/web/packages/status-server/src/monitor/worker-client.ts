import { Worker } from "node:worker_threads";
import { createRequire } from "node:module";
import { cooldownState } from "@agentic-toolkit/deploy-platform/cooldown";
import type { LibsqlConnection } from "../libsql/client";
import type { StatusConfig } from "../config/port";

// Main-thread handle to the monitor worker (worker.ts). The scheduler stays on the
// main thread (single-flight, watchdog, cadence, /health staleness) and each cycle
// becomes one RPC to the worker; console output from the cycle still reaches the
// container logs because workers share the process's stdio.
//
// Self-healing: a cycle that exceeds `cycleTimeoutMs` gets its worker TERMINATED and
// the next cycle spawns a fresh one — a wedged provider chain recovers in-process
// instead of via the supervisor's container restart (which stays as the backstop of
// last resort). An unexpected worker crash likewise fails the in-flight cycle and
// respawns lazily.

export interface CycleRequest {
  seq: number;
  fullSync: boolean;
}

export interface CycleReply {
  seq: number;
  ok: boolean;
  error?: string;
}

/** The `workerData` a monitor worker boots with — plain, structured-clone-safe data
 *  only (it crosses the `worker_threads` boundary), never a live connection or
 *  function. `cooldowns` is attached by the client at spawn time, not supplied by
 *  the host — see {@link MonitorWorkerClient.spawn}. */
export interface MonitorWorkerData {
  db: LibsqlConnection;
  config: StatusConfig;
  cooldowns?: SharedArrayBuffer;
}

interface Pending {
  resolve: () => void;
  reject: (err: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

export class MonitorWorkerClient {
  private worker: Worker | null = null;
  private readonly pending = new Map<number, Pending>();
  private seq = 0;

  constructor(
    private readonly opts: {
      cycleTimeoutMs: number;
      workerData: { db: LibsqlConnection; config: StatusConfig };
    },
  ) {}

  /** Run one monitor cycle on the worker. Rejects on cycle error, worker crash, or
   *  timeout (after which the worker is terminated and respawned on the next call). */
  async runCycle(fullSync: boolean): Promise<void> {
    const worker = (this.worker ??= this.spawn());
    const seq = ++this.seq;
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(seq);
        // The worker is presumed wedged on an un-timed-out await — kill the whole
        // thread so its abandoned work stops consuming the container, and let the
        // next cycle start clean. (terminate() also fires 'exit', which is why
        // failAll below must tolerate an already-settled entry.)
        this.worker = null;
        void worker.terminate();
        reject(new Error(`monitor cycle exceeded ${this.opts.cycleTimeoutMs}ms — worker terminated; next cycle respawns it`));
      }, this.opts.cycleTimeoutMs);
      this.pending.set(seq, { resolve, reject, timer });
      worker.postMessage({ seq, fullSync } satisfies CycleRequest);
    });
  }

  private spawn(): Worker {
    // Resolved through THIS package's own `exports` map — never a relative path to
    // worker.ts — so the entry is always the package's BUILT dist, regardless of
    // whether the host installed via a workspace link or a vendored+hard-linked
    // copy. A container image ships no `tsx` and no TypeScript loader, so spawning
    // the source file directly would work in dev and die on first boot in prod;
    // resolving "@agentic-toolkit/status-server/worker" instead always lands on
    // `dist/monitor/worker.js`, the only form guaranteed runnable in that container.
    const entry = createRequire(import.meta.url).resolve("@agentic-toolkit/status-server/worker");
    // The provider-cooldown state rides along as workerData: the cycle (here) and
    // the API thread's dashboard enumerations poll the SAME provider tokens, so a
    // 429 either one sees has to back BOTH off. A respawned worker re-adopts the
    // same buffer, so an in-force cooldown survives the respawn.
    const worker = new Worker(entry, {
      workerData: {
        ...this.opts.workerData,
        cooldowns: cooldownState(),
      } satisfies MonitorWorkerData,
    });
    worker.on("message", (msg: CycleReply) => {
      const entry = this.pending.get(msg.seq);
      if (!entry) return; // reply from a cycle the timeout already abandoned
      this.pending.delete(msg.seq);
      clearTimeout(entry.timer);
      if (msg.ok) entry.resolve();
      else entry.reject(new Error(msg.error ?? "monitor cycle failed"));
    });
    worker.on("error", (err: Error) => this.failAll(worker, `monitor worker crashed: ${err.message}`));
    worker.on("exit", (code) => this.failAll(worker, `monitor worker exited (${code})`));
    return worker;
  }

  /** Fail every in-flight cycle and drop the worker so the next call respawns. */
  private failAll(worker: Worker, reason: string): void {
    if (this.worker === worker) this.worker = null;
    for (const [seq, entry] of this.pending) {
      this.pending.delete(seq);
      clearTimeout(entry.timer);
      entry.reject(new Error(reason));
    }
  }
}
