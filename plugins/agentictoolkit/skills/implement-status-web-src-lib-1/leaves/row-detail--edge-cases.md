<!-- leaf: implement-status-web-src-lib-1/row-detail--edge-cases · source: status-web-src-lib-row-detail.md -->

# Row Detail

**Rules** (cite as `implement-status-web-src-lib-1/row-detail--edge-cases#<slug>`):

- `null-platform` MUST — A row with platform: null MUST be treated as a deploy row with no platform name. platformText, platformLink and …
- `empty-platform-string` MUST — platform: "" MUST behave like null, because the platform-name test is a truthiness check.
- `unknown-platform` MUST — A platform platformLabel does not know MUST still produce a platform name, its own key lower-cased (for example …
- `endpoint-with-no-url` MUST — An endpoint row with both liveUrl and sourceUrl null MUST use row.name as the title and null as titleUrl.
- `empty-string-urls` MUST — The title and link fallbacks use ??, which does not skip an empty string. An empty liveUrl on an endpoint row MUST give …
- `malformed-endpoint-url` MUST — A liveUrl that new URL cannot parse MUST become the title unchanged. Because title and titleUrl are then equal, the url …
- `empty-at` MUST — at is a required string. An empty at with no downSince MUST give since "", since ?? does not skip it. The serializer …
- `empty-detail` MUST — detail: "" MUST give problem null and problemLink null.
- `zero-values` MUST — statusCode: 0 and responseTimeMs: 0 MUST be kept. They appear as 0 and 0ms in both the detail and the text.
- `resolved-deploy-row` MUST — A status word starting with [ MUST suppress platformText, platformLink and deployOutcome, even when the tone is good.
- `commit-body-equal-to-subject` MUST — A commitBody equal to commitSubject MUST NOT be appended to the text.
- `multi-line-error-text` MUST — errorText MUST be emitted verbatim, including its internal newlines, with no escaping or truncation.

## Edge Cases

- **Null platform**: A row with `platform: null` MUST be treated as a deploy row with no platform name. `platformText`, `platformLink` and `deployOutcome` MUST be null.
- **Empty platform string**: `platform: ""` MUST behave like `null`, because the platform-name test is a truthiness check.
- **Unknown platform**: A platform `platformLabel` does not know MUST still produce a platform name, its own key lower-cased (for example `fly-io`). A tone of `bad` or `good` then yields a deploy outcome.
- **Endpoint with no URL**: An endpoint row with both `liveUrl` and `sourceUrl` null MUST use `row.name` as the title and `null` as `titleUrl`.
- **Empty-string URLs**: The title and link fallbacks use `??`, which does not skip an empty string. An empty `liveUrl` on an endpoint row MUST give `titleUrl` `""` and title `row.name`. The serializer then omits both the `url` and `link` lines.
- **Malformed endpoint URL**: A `liveUrl` that `new URL` cannot parse MUST become the title unchanged. Because title and `titleUrl` are then equal, the `url` line MUST be omitted.
- **Empty `at`**: `at` is a required string. An empty `at` with no `downSince` MUST give `since` `""`, since `??` does not skip it. The serializer then omits the `since` line.
- **Empty detail**: `detail: ""` MUST give `problem` null and `problemLink` null.
- **Zero values**: `statusCode: 0` and `responseTimeMs: 0` MUST be kept. They appear as `0` and `0ms` in both the detail and the text.
- **Resolved deploy row**: A status word starting with `[` MUST suppress `platformText`, `platformLink` and `deployOutcome`, even when the tone is `good`.
- **Commit body equal to subject**: A `commitBody` equal to `commitSubject` MUST NOT be appended to the text.
- **Multi-line error text**: `errorText` MUST be emitted verbatim, including its internal newlines, with no escaping or truncation.
- **Error states, offline, timeouts, cancellation**: Not applicable. The module performs no I/O, has no dependency that can fail, and cannot be cancelled or time out.
- **Concurrent calls**: Not applicable. The functions are pure and run on the single JavaScript thread.
