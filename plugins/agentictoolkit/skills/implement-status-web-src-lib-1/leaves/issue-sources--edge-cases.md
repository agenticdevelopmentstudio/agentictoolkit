<!-- leaf: implement-status-web-src-lib-1/issue-sources--edge-cases · source: status-web-src-lib-issue-sources.md -->

# Issue Sources

**Rules** (cite as `implement-status-web-src-lib-1/issue-sources--edge-cases#<slug>`):

- `empty-string` MUST — isIssueSource("") MUST return false. No member is empty.
- `case-and-whitespace-variants` MUST — "DNS", "Http" and " http" MUST return false. The guard does no normalization, so a caller with untrimmed input has to …
- `integration-spelling-of-cloudflare` MUST — isIssueSource("cloudflare") MUST return false. The deploy-integration vocabulary spells the platform "cloudflare", and …
- `a-source-the-server-emits-that-the-client-lacks` MUST — If the server adds a member to its union and the client is not updated, SOURCE_LABEL[x] MUST yield undefined and …
- `unattributed-rows` MUST — An activity row with no attributed source falls back to its kind (for example "deploy"), per the comment in …
- `non-string-input-at-runtime` MUST — The signature takes string. A JavaScript caller that passes undefined, null or a number MUST get false, because …
- `long-running-builds` MUST — A deploy BUILDING for more than 30 minutes MUST NOT become a client-side Problem. Any stuck verdict arrives from the …

## Edge Cases

- **Empty string**: `isIssueSource("")` MUST return `false`. No member is empty.
- **Case and whitespace variants**: `"DNS"`, `"Http"` and `" http"` MUST return `false`. The guard does no normalization, so a caller with untrimmed input has to normalize first.
- **Integration spelling of Cloudflare**: `isIssueSource("cloudflare")` MUST return `false`. The deploy-integration vocabulary spells the platform `"cloudflare"`, and the board's target keys canonicalise `"cloudflare-pages"` down to `"cloudflare"`. Only the un-canonicalised `"cloudflare-pages"` passes the guard. `row-model.test.ts` asserts that an activity row's source arrives as `"cloudflare-pages"` so it survives the source filter's default seed.
- **A source the server emits that the client lacks**: If the server adds a member to its union and the client is not updated, `SOURCE_LABEL[x]` MUST yield `undefined` and `isIssueSource(x)` MUST return `false`. Callers that index `SOURCE_LABEL` directly with a value typed `IssueSource` (for example `GlobalPanel.tsx` and the `ActivityPanel.tsx` checkbox label) then render `undefined`; `row-model.ts` narrows first and shows the raw string instead. The module's own doc comment states this failure, and the owner of the fix is whoever edits the server union.
- **Unattributed rows**: An activity row with no attributed source falls back to its `kind` (for example `"deploy"`), per the comment in `row-model.ts`. `isIssueSource` MUST return `false` for such a string, and the caller shows it unlabeled.
- **Non-string input at runtime**: The signature takes `string`. A JavaScript caller that passes `undefined`, `null` or a number MUST get `false`, because `Array.prototype.includes` does not throw and no member equals a non-string.
- **Mutation of ISSUE_SOURCES**: The array is typed mutable. A consumer that pushed to or sorted it in place would change the filter order and the guard's answers for every other consumer. No consumer in status-web does so; they only call `filter` and `includes`, which return new values.
- **Long-running builds**: A deploy BUILDING for more than 30 minutes MUST NOT become a client-side Problem. Any stuck verdict arrives from the backend on the board.
- **Null, boundary and error states**: There are no numeric inputs and no I/O. The only numeric export is the fixed constant `STUCK_DEPLOY_MS`. The module cannot fail at runtime.
- **Concurrent access**: Not applicable. The exports are never mutated and JavaScript runs them on one thread.
- **Offline or disconnected**: Not applicable. The module performs no network access.
