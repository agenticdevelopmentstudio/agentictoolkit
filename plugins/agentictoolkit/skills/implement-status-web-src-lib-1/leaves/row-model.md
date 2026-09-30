<!-- leaf: implement-status-web-src-lib-1/row-model · source: status-web-src-lib-row-model.md -->

# Status Row Model

## Overview

`packages/web/packages/status-web/src/lib/row-model.ts` is "The ONE row model" of the status dashboard (its header comment). Active problems, recently-resolved rows and the activity feed are all built into the single `Row` shape, then rendered by the one `<StatusRow>` through `rowToStatusRowProps`, "so every pane has identical row capabilities (clickable commits, consistent links) and a new field is added in one place".

The module exports:

- `RowTone` and `Row` — the row data shape.
- `problemToRow(p)` and `activityToRow(a)` — spell a server-derived `Problem` or `ActivityRow` (from `board-types.ts`) as a `Row`. "The server has already decided what is a problem, what happened, and when — these builders only spell the row."
- `rowToStatusRowProps(row, nowMs)` — the adapter to `StatusRowProps`.
- `rowSearchText(row)` — the free text the pane filter boxes match against.
- `rowToText(row, nowMs)` and `rowsToText(rows, nowMs)` — clipboard serialization, one tab-separated line per row (used by `ActivityPanel.tsx`'s copy button).
- `commitUrlOf(repo, hash)` — a GitHub commit URL or `null`.
- `STATE_LABEL` — the problem state to status-word table.
- `UNCONFIRMED_AFTER_MS`, `unconfirmedWindowMs(probeIntervalMs?)` and `deployDtoUnconfirmed(d, nowMs, probeIntervalMs?)` — the client's only remaining freshness clock, applied to raw `DeploymentDTO`s by `DeployList.tsx` and `deploy-view.ts`, never to a `Row`.

Every export is a pure, synchronous function or constant. The module performs no I/O, holds no state and is covered by `row-model.test.ts` (Vitest).

