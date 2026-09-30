<!-- leaf: implement-general-1/deploy-engine · source: deploy-engine.md -->

# Deploy Engine

## Overview

Deploy Engine is the headless logic that keeps a monitoring board's endpoints
and sites in sync with what actually exists on Vercel, Railway and
Cloudflare. It has no UI of its own; a status app and a builder app both sit
on top of it. Three concerns are split into files that each stay pure where
possible:

- **Canonicalization** (`canon/index.ts`) — the one definition of a platform
  name, a correlation key, a host's environment label, a site's "apex", a
  registrable domain family, and a slug. Every other file in this component
  imports these rather than re-deriving them, so two files can never disagree
  about what host belongs to what site.
- **Classification** (`classify.ts`) — the one "configured or not?" model,
  computed on two axes (endpoints that need wiring, deploy projects that need
  a monitor) so every UI surface that renders a badge or a banner counts the
  same thing.
- **Planning** (`plan.ts`, `builder-match.ts`) — pure functions from
  "one deploy project + current endpoints/sites" to a plan (`AddPlan`,
  `BuilderSitePlan`). No I/O; trivially unit-testable.
- **Running** (`run.ts`, `builder-match.ts`'s `runBuilderAutoConfigure`) —
  injected-I/O orchestration that applies a plan sequentially, sharing one
  `applySequentially` loop between the status-project runner and the
  builder-site runner so their sequencing and skip-collection semantics can
  never drift apart.
- **Provider adapters** (`providers/vercel.ts`, `providers/railway.ts`,
  `providers/cloudflare.ts`, `providers/host-pick.ts`) — the network calls
  each provider's API needs, each returning a `live`/provenance-tagged
  result so a caller can tell "genuinely empty" from "could not read".
- **Cross-thread rate limiting** (`cooldown/provider-cooldown.ts`) — a
  `SharedArrayBuffer`-backed per-provider cooldown registry read
  synchronously on the hot path of every fetch, shared between the worker
  thread that polls and the API thread that enumerates.
- **Shared utilities** (`util/cached-single-flight.ts`, `util/map-limit.ts`,
  `util/with-timeout.ts`) — a TTL + single-flight cache, a bounded-concurrency
  mapper, and an abort-based timeout, each with exactly one implementation
  reused across the component.

