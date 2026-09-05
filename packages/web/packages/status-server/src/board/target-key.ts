import { platformCanon } from "../monitor/overview";

/**
 * `|` is the separator, so a segment that contains one is ESCAPED, never rejected.
 * `%` → `%25` first, then `|` → `%7C`: escaping the escape character first is what makes
 * the mapping injective, so `unescapeSegment` can invert it exactly.
 *
 * EXPORTED for `errorsTarget`, which mints a two-segment key out of a GlitchTip project
 * slug. That value is not safe by construction — the fetcher falls back to the project's
 * free-form NAME when no slug is present — and an unescaped `|` in it would mint a target
 * that parses back into a different string, so the fold could never match the ledger row
 * it had just written. One escape pair, used by every minter.
 *
 * Rejecting instead was worse than the ambiguity it avoided. A Railway environment named
 * `prod|eu` — free-form, on the only platform that populates that segment — minted no key
 * at all, which meant `rosterTargets` indexed nothing for the entry, `monitoredTargets`
 * omitted it, `deployProblems` could never own its rows, and a FAILED BUILD produced no
 * Problem. Any already-open ledger row then closed as `unmonitored`, which is silent by
 * design. Escaping keeps the round-trip total AND keeps reporting the failure.
 */
export function escapeSegment(s: string): string {
  return s.replace(/%/g, "%25").replace(/\|/g, "%7C");
}

/**
 * The inverse, in ONE left-to-right pass. Two sequential replaces would be a different
 * function: unescaping `%7C` before `%25` can turn the escape of a literal `%7C` back into
 * a separator. One pass consumes each escape where it stands and never re-reads its output.
 */
export function unescapeSegment(s: string): string {
  return s.replace(/%(25|7C)/g, (_m, hex: string) => (hex === "25" ? "%" : "|"));
}

/**
 * The ONE function that mints a board target string. Everything that identifies a
 * deploy target — the ledger's `issues.target`, the roster, the orphan sweep, the
 * client's rendering key — goes through here, so a target has exactly one spelling.
 *
 * Before this existed there were two: `deployTargetKey()` in the vendored canon and a
 * hand-rolled template literal in `issues.ts`, which disagreed about both the env
 * segment and platform canonicalisation. The orphan sweep matched one and not the
 * other, which is how a fixed target could keep a Problem open forever.
 *
 * `id` is the provider's immutable project id when we have one, else the project NAME.
 * Both spellings key the same way, so adopting provider ids per-platform is a
 * per-platform change that never needs a flag day.
 *
 * The env segment is populated for `railway` ONLY. That is a domain fact, not an
 * oversight: one Railway project serves many environments, whereas a Vercel or
 * Cloudflare project IS one environment (its name encodes it — see `envFromProject`).
 *
 * The id and env segments are percent-escaped (see `escapeSegment`), so the output is
 * ALWAYS exactly three segments and `parseBoardTarget` always reads back the inputs — the
 * mint→parse round-trip is total, which is the property the rest of the fold assumes.
 * The platform segment is not escaped: it is `platformCanon`'s output, a fixed vocabulary
 * with neither character in it, and leaving it alone keeps an ordinary key byte-identical
 * to the vendored `deployTargetKey`.
 *
 * Escaping only ever CHANGES a key that the old code could not mint at all (it returned
 * null), so no live ledger row minted by this function can be orphaned by the change. A
 * pre-round-1 row holding a raw four-segment target is a different matter: it never matched
 * a minted key then either, and it closes as `unmonitored` on the next reconcile while the
 * escaped target opens the Problem that row could no longer carry.
 *
 * STILL NULLABLE, deliberately, and this is a departure from the brief's "its return type
 * stops being nullable": escaping removes the separator failure mode, but a missing or
 * unknown platform and a missing/empty id remain unmintable — there is no key to invent for
 * them, and `test/board-target-key.test.ts` pins that null. Every call site already handles
 * it, and the escaping is what deletes the *silent unmonitoring*, which was the defect.
 */
export function boardTargetKey(
  platform: string | null,
  id: string | null,
  environment: string | null,
): string | null {
  const p = platformCanon(platform);
  if (!p || !id) return null;
  // Lowercased BEFORE escaping, so the escape sequences are always upper-case hex and
  // `unescapeSegment` has one spelling to match. (The lowercasing itself is the domain
  // rule that 'Scratch1' and 'scratch1' are one Railway environment.)
  const env = p === "railway" ? (environment?.toLowerCase() ?? "") : "";
  return `${p}|${escapeSegment(id)}|${escapeSegment(env)}`;
}

/** Split a target back into its parts. Null for anything that isn't three segments. */
export function parseBoardTarget(
  target: string,
): { platform: string; id: string; environment: string } | null {
  const parts = target.split("|");
  if (parts.length !== 3) return null;
  const [platform, id, environment] = parts;
  if (!platform || !id) return null;
  // The length check above guarantees a third segment exists (boardTargetKey always emits
  // one, even if empty for non-railway targets) — the `?? ""` only satisfies
  // noUncheckedIndexedAccess's array-destructuring type, it changes no runtime behavior.
  return { platform, id: unescapeSegment(id), environment: unescapeSegment(environment ?? "") };
}
