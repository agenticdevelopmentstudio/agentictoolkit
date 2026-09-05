import type { Row } from "./row-model";
import type { IndicatorState } from "./overview";

/** Problem row → its sublabel phrase. Keyed on the row's status word. */
const SUBLABEL_PHRASE: Record<string, (n: number) => string> = {
  down: (n) => `${n} down`,
  degraded: (n) => `${n} degraded`,
  "build failed": (n) => `${n} failed build${n === 1 ? "" : "s"}`,
  "deploy failed": (n) => `${n} failed deploy${n === 1 ? "" : "s"}`,
  "deployment failed": (n) => `${n} stale deploy${n === 1 ? "" : "s"}`,
  building: (n) => `${n} stuck build${n === 1 ? "" : "s"}`, // a building row only reaches Problems when stuck
  "platform unreachable": (n) => `${n} platform${n === 1 ? "" : "s"} unreachable`,
};

/**
 * The status sublabel — "12/12 endpoints healthy · no failed builds" when clear,
 * or a grouped problem breakdown that accounts for EVERY problem so the parts sum
 * to the indicator count. Shared by the mobile hero and the desktop top-bar pill.
 */
export function buildSublabel(state: IndicatorState, healthyCount: number, servicesLength: number, problems: Row[]): string {
  if (state === "ok") {
    // When the board is operational, a non-healthy endpoint is a transient blip
    // (degraded-within-window) or an un-probed/unknown one — not an incident. So
    // don't print a fraction like "4/5 healthy" that reads as a contradiction
    // next to "ALL SYSTEMS OPERATIONAL"; only claim N/N when truly all-healthy.
    return healthyCount === servicesLength
      ? `${healthyCount}/${servicesLength} endpoints healthy · no failed builds`
      : `${servicesLength} endpoints monitored · no failed builds`;
  }
  const byWord = new Map<string, number>();
  for (const r of problems) byWord.set(r.statusWord, (byWord.get(r.statusWord) ?? 0) + 1);
  const parts: string[] = [];
  for (const [word, fmt] of Object.entries(SUBLABEL_PHRASE)) {
    const n = byWord.get(word) ?? 0;
    if (n > 0) {
      parts.push(fmt(n));
      byWord.delete(word);
    }
  }
  for (const [word, n] of byWord) parts.push(`${n} ${word}`); // any unmapped word
  return parts.join(" · ");
}
