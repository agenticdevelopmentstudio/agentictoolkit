"use client";
import { type ReactElement, useEffect, useState } from "react";

import { PALETTE } from "../lib/colors";
const mono = "var(--mono,ui-monospace,monospace)";

/** m:ss with a floor of 0:00 — exported for tests. */
export function formatRemaining(ms: number): string {
  const totalSeconds = Math.max(0, Math.ceil(ms / 1000));
  const m = Math.floor(totalSeconds / 60);
  const s = totalSeconds % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

/**
 * Live countdown to the next poll — just "m:ss", flipping to "checking…" while a
 * poll is in flight (it would otherwise sit frozen at 0:00 waiting for the result).
 * Isolated in its own component so the 1s tick re-renders only this line.
 */
export function NextCheckCountdown({ nextPollAt, polling }: { nextPollAt: number | null; polling: boolean }): ReactElement {
  const [nowMs, setNowMs] = useState<number>(() => Date.now());

  useEffect(() => {
    const t = setInterval(() => setNowMs(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  const remaining = nextPollAt === null ? 0 : nextPollAt - nowMs;
  // Fixed width + right-align so swapping between "checking…" and "m:ss" (and
  // before the first poll, nothing) never reflows the refresh button beside it.
  // Monospace already keeps the ticking digits from jittering.
  return (
    <span
      aria-label="time until next check"
      style={{ display: "inline-block", width: 58, textAlign: "right", fontFamily: mono, fontSize: 12, color: PALETTE.muted, whiteSpace: "nowrap" }}
    >
      {nextPollAt === null ? "" : polling ? "checking…" : formatRemaining(Math.max(0, remaining))}
    </span>
  );
}
