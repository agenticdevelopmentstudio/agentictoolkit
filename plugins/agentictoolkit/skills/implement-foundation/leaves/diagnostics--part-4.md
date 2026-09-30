<!-- leaf: implement-foundation/diagnostics--part-4 · source: foundation-diagnostics.md -->

# JITAvailability, UpstreamDivergence & UpstreamDivergenceLedger — continued (part 4)

## Design Decisions

**Decision**: `JITAvailability` determines JIT availability by reading this
process's code-signing flags and entitlement, rather than by attempting an
actual `mmap` with `MAP_JIT` and observing whether the kernel grants it.
**Rationale**: Per the type's own doc comment, the `mmap`-based probe was
written first and measured against three signing configurations (hardened
and entitled, hardened and bare, and neither); it succeeded in all three,
because the kernel does not enforce the entitlement at mapping time. A probe
built on that call could never fail and would have shipped as a check that
silently never fires — the same defect class it exists to catch. Reading the
signature instead discriminates between the three configurations, which is
the whole reason the two boolean readings are what this type reads.
**Approved**: pending

**Decision**: `UpstreamDivergence.Detection` distinguishes `.counted`
divergences (those with a live call site that can record a hit) from
`.declared` divergences (those with no call site, because the narrowing
takes the form of a capability this app never advertised upstream).
**Rationale**: A `.counted` row reading zero is real evidence that nothing
tripped it; a `.declared` row has no meaningful count at all, since nothing
in the app could record one even if the narrowing mattered constantly. A
report that rendered both as "0" without the label would invite exactly the
wrong conclusion about the second kind — this is why `Detection` is a
distinct field on every entry rather than a derived property, and why the
catalogue currently keeps `.counted` entries in the majority (five of six).
**Approved**: pending

**Decision**: `UpstreamDivergenceLedger.publish()` takes a second lock,
`publishLock`, around taking its snapshot of `rows` and sending it to
`subject`, in addition to the `lock` that already guards `rows` itself.
**Rationale**: The type's own doc comment describes the bug this fixes: two
writers that each compute their snapshot under `lock` and send it only after
releasing leave the send order to the scheduler, so a recorder overtaken in
that gap by a concurrent `clear()` could publish rows the clear had already
removed — and because `CurrentValueSubject` replays only its last value,
that stale publish would never self-correct. Reading the snapshot inside the
second lock's exclusion guarantees whoever finishes last publishes the
newest state, whichever order the underlying mutations actually committed
in.
**Approved**: pending

**Decision**: `UpstreamDivergenceLedger` keeps no eviction policy, expiry,
or row cap — rows accumulate for the process's lifetime and are only ever
cleared by an explicit `clear()` call.
**Rationale**: The type's own doc comment calls this deliberate: the ledger
is "cheap: an in-memory dictionary behind a lock, no persistence, cleared
when the app quits," and a ledger that survived launches would accumulate
rows from code that has since changed — the same failure mode as any stale
diagnostic file. The source does not, however, document a bound on how large
`rows` may grow within a single long-running session before the next
`clear()`; see the "Unbounded ledger growth" edge case.
**Approved**: pending
