<!-- leaf: implement-extension-host-core-1/extensions-extension-update-check--edge-cases · source: extension-host-core-extensions-extension-update-check.md -->

# ExtensionUpdateCheck

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-update-check--edge-cases#<slug>`):

- `empty-installed-array` MUST — check([]) MUST return a report with both arrays empty; this is not an error condition (MUST, traced to …
- `publisher-is-nil` MUST — update(for:) MUST throw .noPublisher before making any request; in check(_:) this surfaces as a .noPublisher …
- `publisher-is-the-empty-string` MUST — treated identically to nil — the guard is !publisher.isEmpty, so a manifest that decoded publisher as "" MUST also …
- `installed-or-published-version-string-does-not-parse-as-major-minor-patch` MUST (e.g. `"nightly-build"`, a prerelease suffix such as `"1.0.0-rc.1"`, or any string `SemanticVersion.init?` rejects) — MUST throw .versionNotComparable rather than compare on string inequality (MUST, traced to incomparableVersionsThrow; …
- `published-version-equal-to-or-older-than-installed` MUST — MUST return nil from update(for:) — not an error, and specifically not an offered downgrade, since the registry can …
- `published-version-is-newer-but-fails-the-installability-gate` MUST (`engineIncompatible`, `platformSpecific`, `noUniversalBuild`, or `engineRangeUnreadable`) — MUST return nil from update(for:), identical to the "no update" outcome for an equal or older version — a caller cannot …
- `registry-answers-404` MUST — classified as .notPublished, the expected outcome for a sideloaded, unpublished, or private extension — this MUST NOT …
- `registry-answers-any-other-non-2xx-status-or-the-request-fails-to-reach-the-registry-at-all` MUST (a malformed registry URL, an undecodable response body, a transport-level failure such as no network connectivity or a request timeout, or `URLSession`/structured-concurrency task cancellation surfacing as a thrown error) — all of these MUST classify as .registryUnreachable, the same reason a 503 produces — the source distinguishes only "no …
- `concurrent-lookups-and-their-completion-order` MUST — check(_:) MUST run every extension's lookup concurrently via withTaskGroup, and the outcome arrays MUST be independent …

## Edge Cases

- **Empty `installed` array**: `check([])` MUST return a report with both
  arrays empty; this is not an error condition (MUST, traced to
  `emptyInputIsEmptyReport`; requirement `empty-input-empty-report`).
- **Publisher is `nil`**: `update(for:)` MUST throw `.noPublisher` before
  making any request; in `check(_:)` this surfaces as a `.noPublisher`
  `notCheckable` entry rather than a thrown error (MUST, traced to
  `noPublisherThrows` and `aManifestWithNoPublisherSaysSo`).
- **Publisher is the empty string**: treated identically to `nil` — the guard
  is `!publisher.isEmpty`, so a manifest that decoded `publisher` as `""`
  MUST also throw `.noPublisher` (MUST, traced to the source).
- **Installed or published version string does not parse as
  `major[.minor[.patch]]`** (e.g. `"nightly-build"`, a prerelease suffix such
  as `"1.0.0-rc.1"`, or any string `SemanticVersion.init?` rejects): MUST
  throw `.versionNotComparable` rather than compare on string inequality
  (MUST, traced to `incomparableVersionsThrow`; `SemanticVersion.init?` is
  documented, in `SemanticVersion.swift`, as parsing only bare
  `major.minor.patch` with no prerelease or build-metadata grammar, so any
  such string reaches this path as an unparseable version, not a special
  case `ExtensionUpdateCheck` itself distinguishes).
- **Published version equal to or older than installed**: MUST return `nil`
  from `update(for:)` — not an error, and specifically not an offered
  downgrade, since the registry can legitimately be behind a self-hosted
  mirror mid-sync (MUST, traced to `sameVersionIsNotAnUpdate` and
  `olderPublishedVersionIsNotAnUpdate`).
- **Published version is newer but fails the installability gate**
  (`engineIncompatible`, `platformSpecific`, `noUniversalBuild`, or
  `engineRangeUnreadable`): MUST return `nil` from `update(for:)`, identical
  to the "no update" outcome for an equal or older version — a caller cannot
  distinguish "already current" from "a newer, uninstallable build exists"
  from the return value of `update(for:)` alone (MUST, traced to
  `newerButIncompatibleIsNotOffered` and `newerPlatformSpecificIsNotOffered`
  for two of the four `OpenVSXInstallability` non-`.installable` cases; the
  other two, `.noUniversalBuild` and `.engineRangeUnreadable`, are gated by
  the same `guard installability == .installable else { return nil }` but have no dedicated test in
  `ExtensionUpdateCheckTests.swift`).
- **Registry answers 404**: classified as `.notPublished`, the expected
  outcome for a sideloaded, unpublished, or private extension — this MUST
  NOT fail the enclosing `check(_:)` call (MUST, traced to
  `oneUnknownExtensionDoesNotFailTheCheck`).
- **Registry answers any other non-2xx status, or the request fails to
  reach the registry at all** (a malformed registry URL, an undecodable
  response body, a transport-level failure such as no network connectivity
  or a request timeout, or `URLSession`/structured-concurrency task
  cancellation surfacing as a thrown error): all of these MUST classify as
  `.registryUnreachable`, the same reason a `503` produces — the source
  distinguishes only "no such extension" (404) from "no usable answer" (every
  other failure), and does not further distinguish among the causes of "no
  usable answer" (MUST, traced to `aFailingRegistryIsUnreachableRatherThanUnknown`
  and the `default:` branch).
- **Concurrent lookups, and their completion order**: `check(_:)` MUST run
  every extension's lookup concurrently via `withTaskGroup`, and the outcome
  arrays MUST be independent of which task completes first — this is
  guaranteed by the explicit `sorted` calls after the `for await` loop
  collects every result, not by any ordering the task group itself provides
  (MUST, traced to `resultsAreSorted`, which stubs three registry answers
  and asserts the identifier order of the result regardless of arrival
  order).
- **Duplicate entries in `installed` sharing the same identifier**: not
  addressed by the source as a distinct case — `check(_:)` adds one task per
  array element with no de-duplication by `identifier`, so two entries for
  the same extension produce two independent lookups and, in general, two
  entries in the resulting `updates` or `notCheckable` array. Because
  `sorted(by:)` in Swift is a stable sort, the relative order between two
  entries that share an identical `identifier` after sorting is whichever
  order the concurrent lookups happened to complete in, which is not
  deterministic across runs (fact, traced to the absence of any
  identifier-grouping step in `check(_:)`).
- **A dependency (the registry) is unavailable for the whole call, not just
  one extension**: no distinct code path exists for "the registry as a
  whole is down" versus "this one lookup failed" — every extension whose
  lookup reaches the registry and gets no usable answer is reported
  individually as `.registryUnreachable` in `notCheckable`; there is no
  fail-fast short-circuit that stops issuing further lookups once one has
  failed this way (fact, traced to `outcome(for:)`'s per-task `catch`, which is scoped to one extension with no shared state across
  tasks).
- **Offline / disconnected state**: not a state this component detects or
  reports as such — a lost connection during a lookup throws a transport
  error from `OpenVSXClient`, which `outcome(for:)`'s `default:` branch
  classifies as `.registryUnreachable`, identically to a reachable-but-failing
  registry (fact, traced to the same `default:` branch;
  `ExtensionUpdateCheck` has no separate concept of "offline").
