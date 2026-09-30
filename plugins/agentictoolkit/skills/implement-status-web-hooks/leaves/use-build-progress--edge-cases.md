<!-- leaf: implement-status-web-hooks/use-build-progress--edge-cases · source: status-web-hooks-use-build-progress.md -->

# useBuildProgress

**Rules** (cite as `implement-status-web-hooks/use-build-progress--edge-cases#<slug>`):

- `empty-activity` MUST — [] MUST yield visible: false, total: 0, completed: 0, pct: 0, complete: false, and the accumulation effect MUST return …
- `build-drops-out-of-the-feed` MUST — A cohort id missing from the next snapshot MUST count as completed; the hook cannot distinguish "finished" from "paged …
- `wedged-build` MUST — A build toned "progress" indefinitely MUST keep the bar visible below 100% until the server re-tones the row; there is …
- `build-re-enters-progress` MUST — A cohort id that settled and then is toned "progress" again MUST count as not completed again; if this happens during …
- `new-build-during-the-hold` MUST — A new in-flight id arriving before 2000 ms elapse MUST join the existing cohort, and total MUST include the …
- `same-id-after-reset` MUST — After the cohort resets, an id seen in flight again MUST start a new cohort of one.
- `duplicate-ids-in-one-snapshot` MUST — They MUST collapse to one cohort member.
- `tones-other-than-progress` MUST — "good", "bad", "neutral" and "stale" MUST all count as not in flight.
- `malformed-input` MUST — The hook relies on the ActivityRow type; it performs no runtime validation, and a row missing kind, step or tone MUST …
- `environment-filter-changes` MUST — If the caller's filtered array stops including a cohort build, that build MUST count as completed, exactly like a row …
- `unmount` MUST — A pending hold timer MUST be cleared by the effect cleanup.

## Edge Cases

- **Empty activity**: `[]` MUST yield `visible: false`, `total: 0`, `completed: 0`, `pct: 0`, `complete: false`, and the accumulation effect MUST return early without touching state.
- **Build drops out of the feed**: A cohort id missing from the next snapshot MUST count as completed; the hook cannot distinguish "finished" from "paged out" and MUST NOT try.
- **Wedged build**: A build toned `"progress"` indefinitely MUST keep the bar visible below 100% until the server re-tones the row; there is no client timeout.
- **Build re-enters progress**: A cohort id that settled and then is toned `"progress"` again MUST count as not completed again; if this happens during the hold it MUST cancel the reset.
- **New build during the hold**: A new in-flight id arriving before 2000 ms elapse MUST join the existing cohort, and `total` MUST include the already-completed builds.
- **Same id after reset**: After the cohort resets, an id seen in flight again MUST start a new cohort of one.
- **Duplicate ids in one snapshot**: They MUST collapse to one cohort member.
- **Tones other than `"progress"`**: `"good"`, `"bad"`, `"neutral"` and `"stale"` MUST all count as not in flight.
- **Malformed input**: The hook relies on the `ActivityRow` type; it performs no runtime validation, and a row missing `kind`, `step` or `tone` MUST simply fail the in-flight predicate.
- **Environment filter changes**: If the caller's filtered array stops including a cohort build, that build MUST count as completed, exactly like a row leaving the feed.
- **Concurrent access**: Not applicable beyond the threading requirement; the hook runs on the single JS thread and each render sees one snapshot.
- **Network or offline**: Not applicable; the hook does no I/O. A stale board simply keeps the last snapshot's rows, and the bar reflects them unchanged.
- **Unmount**: A pending hold timer MUST be cleared by the effect cleanup.
