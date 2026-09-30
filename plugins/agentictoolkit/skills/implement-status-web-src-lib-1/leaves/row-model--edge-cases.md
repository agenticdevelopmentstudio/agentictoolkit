<!-- leaf: implement-status-web-src-lib-1/row-model--edge-cases · source: status-web-src-lib-row-model.md -->

# Status Row Model

**Rules** (cite as `implement-status-web-src-lib-1/row-model--edge-cases#<slug>`):

- `null-commit-fields` MUST — A null commitHash, commitRepo or commitMessage MUST yield sha, commitUrl and message of null, and commitBody of null …
- `empty-strings` MUST — commitUrlOf("", "abc") and commitUrlOf("o/r", "") MUST return null. An empty environment MUST produce an empty env …
- `unknown-problem-state` MUST — A state absent from STATE_LABEL MUST render verbatim (row-model-005). Because STATE_LABEL is a plain object, a state …
- `unknown-source` MUST — A Row.source that is not an IssueSource (an activity row's kind fallback) MUST appear verbatim in the clipboard source …
- `malformed-at` MUST — Row.at is documented as an ISO timestamp. An unparseable value makes timeAgo compute NaN and return "NaNd"; this MUST …
- `future-at` MUST — A timestamp later than nowMs gives a negative elapsed time and MUST render "just now".
- `boundary-of-the-demotion-window` MUST — Elapsed time exactly equal to the window MUST NOT demote (row-model-032); one millisecond more MUST (row-model-028).
- `missing-probe-interval` MUST — An undefined probeIntervalMs (older backend) MUST use the 10-minute floor; an interval of 120000 ms or less also yields …
- `unparseable-deploy-clock` MUST — An in-flight deploy whose phaseConfirmedAt (or fallback createdAt) does not parse MUST demote — fail closed …
- `commit-subject-over-200-characters` MUST — message MUST be the first 200 characters with no ellipsis, while commitBody and rowSearchText keep the full text.

## Edge Cases

- **Null commit fields**: A null `commitHash`, `commitRepo` or `commitMessage` MUST yield `sha`, `commitUrl` and `message` of null, and `commitBody` of null (row-model-003).
- **Empty strings**: `commitUrlOf("", "abc")` and `commitUrlOf("o/r", "")` MUST return null. An empty `environment` MUST produce an empty env column in `rowToText`, and an empty `sha` or `message` MUST be dropped from the commit column.
- **Unknown problem state**: A state absent from `STATE_LABEL` MUST render verbatim (row-model-005). Because `STATE_LABEL` is a plain object, a state spelled like an inherited object member (for example `"constructor"`) resolves to that inherited value rather than falling back; the server's documented state vocabulary (`Problem.state` doc comment) contains no such names.
- **Unknown source**: A `Row.source` that is not an `IssueSource` (an activity row's `kind` fallback) MUST appear verbatim in the clipboard source column (row-model-025).
- **Malformed `at`**: `Row.at` is documented as an ISO timestamp. An unparseable value makes `timeAgo` compute `NaN` and return `"NaNd"`; this MUST be treated as a caller precondition violation, not handled here.
- **Future `at`**: A timestamp later than `nowMs` gives a negative elapsed time and MUST render `"just now"`.
- **Boundary of the demotion window**: Elapsed time exactly equal to the window MUST NOT demote (row-model-032); one millisecond more MUST (row-model-028).
- **Missing probe interval**: An undefined `probeIntervalMs` (older backend) MUST use the 10-minute floor; an interval of 120000 ms or less also yields the floor because five times it is at most 600000.
- **Unparseable deploy clock**: An in-flight deploy whose `phaseConfirmedAt` (or fallback `createdAt`) does not parse MUST demote — fail closed (row-model-030). A terminal deploy with an unparseable clock MUST NOT demote, since the in-flight test runs first.
- **Tabs and newlines in clipboard fields**: Not escaped; see the open question on text-field-escaping (row-model-033).
- **Commit subject over 200 characters**: `message` MUST be the first 200 characters with no ellipsis, while `commitBody` and `rowSearchText` keep the full text.
- **Concurrent access**: Not applicable — every export is pure and synchronous on the single JavaScript thread, so calls cannot interleave.
- **Error states**: Not applicable — no function touches a network, file or other dependency, and none throws for inputs of its declared types.
- **Offline or disconnected state**: Not applicable — no network is involved; freshness of the server data is judged elsewhere (`board-staleness.ts`, `snapshot-staleness.ts`).
