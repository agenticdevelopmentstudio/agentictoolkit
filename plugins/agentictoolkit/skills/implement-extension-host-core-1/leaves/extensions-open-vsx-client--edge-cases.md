<!-- leaf: implement-extension-host-core-1/extensions-open-vsx-client--edge-cases · source: extension-host-core-extensions-open-vsx-client.md -->

# OpenVSXClient

**Rules** (cite as `implement-extension-host-core-1/extensions-open-vsx-client--edge-cases#<slug>`):

- `null-and-empty-input` MUST — search's query MUST default to "" and be treated as the browse case, not an error (search-default-query). An empty …
- `boundary-values` MUST — A body of exactly maximumArtifactBytes MUST be accepted in full; a body one byte over MUST be refused with …
- `concurrent-access` MUST — Concurrent calls to any of search, detail, data, or text on the same OpenVSXClient value MUST each run against their …
- `error-states` MUST — A non-2xx HTTP status from the registry MUST be reported as OpenVSXError.requestFailed(url:status:) before any attempt …
- `offline-disconnected-state` MUST — Connectivity lost mid-transfer, after the response headers arrive but before the full body does, MUST surface as the …
- `malformed-input` MUST — namespace, name, or version values containing /, \, :, a leading ., or a control character — including a bare / with no …
- `malformed-input-2` MUST — An artifact URL using file:, data:, plain http:, or any scheme other than https, or an https URL with no host, MUST be …
- `cancellation` MUST — Cancelling the awaiting Task MUST cancel the in-flight URLSessionDataTask rather than let it run to completion …
- `registry-answers-with-an-oversized-error-page` MUST — An HTTP error status (404, 503, or any non-2xx) accompanied by a body larger than the relevant ceiling MUST still be …

## Edge Cases

- **Null and empty input**: `search`'s `query` MUST default to `""` and be
  treated as the browse case, not an error (`search-default-query`). An
  empty `namespace` or `name` passed to `detail` MUST be refused by
  `ExtensionIdentityComponent.isSafe`'s empty-value rule and reported as
  `OpenVSXError.unsafeIdentity(field:value:)`, never sent as a request
  (`detail-identity-validated`; `ExtensionIdentityComponent.swift`'s
  `empty-value-refused` rule).
- **Boundary values**: A body of exactly `maximumArtifactBytes` MUST be
  accepted in full; a body one byte over MUST be refused with
  `artifactTooLarge` even with no `Content-Length` header present to trigger
  an early refusal (tests `aBodyOfExactlyTheCapIsAccepted`,
  `aBodyOneByteOverTheCapIsRefused`). The two published ceilings,
  `defaultMaximumArtifactBytes` and `defaultMaximumMetadataBytes`, MUST
  remain distinct values three orders of magnitude apart
  (`artifact-and-metadata-ceilings-are-distinct`).
- **Concurrent access**: Concurrent calls to any of `search`, `detail`,
  `data`, or `text` on the same `OpenVSXClient` value MUST each run against
  their own `URLSessionDataTask`, tracked by `BoundedBodyLoader`'s internal
  `State` keyed on `taskIdentifier` behind one lock, so no call's outcome
  MUST depend on another concurrent call's timing or ordering
  (`independent-concurrent-calls`).
- **Error states (dependency unavailable)**: A non-2xx HTTP status from the
  registry MUST be reported as `OpenVSXError.requestFailed(url:status:)`
  before any attempt to decode the body, for both metadata reads and
  artifact reads (`status-checked-before-decode`,
  `status-outranks-size-ceiling`). A session-level failure that arrives
  before or during the transfer — DNS failure, TLS failure, connection
  refused, or a client-imposed timeout — is NOT wrapped in `OpenVSXError`; it
  MUST propagate to the caller as whatever error type `URLSession` produced,
  because `body` only intercepts `BoundedBodyLoader.Failure.tooLarge`
  (`network-failure-propagates-untyped`). This component sets no
  request-specific timeout of its own; the effective timeout is whatever
  `URLSessionConfiguration` the caller's `session` argument carries (source:
  absence of any `timeoutInterval` assignment in `init` or elsewhere in the
  file).
- **Offline / disconnected state**: Connectivity lost mid-transfer, after the
  response headers arrive but before the full body does, MUST surface as the
  underlying `URLSessionDataDelegate.didCompleteWithError` error via the same
  untyped-propagation path described above; any bytes already accumulated
  for that transfer are discarded rather than returned as a partial result —
  `search`, `detail`, `data`, and `text` each return either the complete
  decoded value or a thrown error, never a partial `Data` or `String`
  (`BoundedBodyLoader.swift`;
  `network-failure-propagates-untyped`).
- **Malformed input (path-traversal identity)**: `namespace`, `name`, or
  `version` values containing `/`, `\`, `:`, a leading `.`, or a control
  character — including a bare `/` with no `..` at all — MUST be refused by
  `detail-identity-validated` before any request is composed, since
  `appendingPathComponent` performs no escaping and would otherwise let such
  a value address an endpoint outside the intended one (source comment; tests `detailRefusesATraversingNamespace`,
  `detailRefusesATraversingNameAndVersion`).
- **Malformed input (artifact URL scheme)**: An artifact URL using `file:`,
  `data:`, plain `http:`, or any scheme other than `https`, or an `https`
  URL with no host, MUST be refused by `requireFetchable` before any request
  is made — every artifact URL `data(at:)` and `text(at:)` are given
  originates from the registry's own `files`/`downloads` JSON, so a
  malicious or misconfigured registry answer is the threat this guards
  against, not a typo by the caller (doc comment;
  `artifact-scheme-and-host-required`).
- **Cancellation**: Cancelling the awaiting `Task` MUST cancel the
  in-flight `URLSessionDataTask` rather than let it run to completion
  unobserved (`cancellation-stops-the-transfer`).
- **Registry answers with an oversized error page**: An HTTP error status
  (404, 503, or any non-2xx) accompanied by a body larger than the relevant
  ceiling MUST still be reported as `requestFailed` with that status, never
  as `artifactTooLarge`/`responseTooLarge` — a long error page from a proxy
  or a down registry MUST NOT be misreported as "the answer was too large"
  (`status-outranks-size-ceiling`; tests `anErrorStatusOutranksTheCeiling`,
  `aMissingArtifactIsReportedAsMissing`).
