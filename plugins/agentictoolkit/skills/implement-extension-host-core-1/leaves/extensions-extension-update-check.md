<!-- leaf: implement-extension-host-core-1/extensions-extension-update-check · source: extension-host-core-extensions-extension-update-check.md -->

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-update-check#<slug>`):

- `default-client` MUST
- `default-host-version` MUST
- `publisher-required` MUST
- `registry-lookup-by-manifest-fields` MUST
- `latest-version-requested` MUST
- `versions-must-both-parse` MUST
- `no-downgrade-offered` MUST
- `installability-gate` MUST
- `update-value-shape` MUST
- `concurrent-per-extension-lookup` MUST
- `per-lookup-failure-isolation` MUST
- `check-never-throws` MUST
- `updates-sorted-by-identifier` MUST
- `unavailable-sorted-by-identifier` MUST
- `empty-input-empty-report` MUST
- `error-classification-not-published` MUST
- `error-classification-no-publisher` MUST
- `error-classification-version-not-comparable` MUST
- `error-classification-default-unreachable` MUST
- `failure-logged-at-debug` MUST
- `report-carries-both-arrays` MUST
- `value-type-equatability` MUST
- `error-type-equatability` MUST
- `non-sendable-lookup-result-type` MUST

# ExtensionUpdateCheck

## Overview

`ExtensionUpdateCheck` is a stateless `Sendable` struct that answers whether
one installed extension — or a whole list of them — has a newer version this
host could actually run. It holds an `OpenVSXClient` and the host's declared
`SemanticVersion`, and its two public operations are `update(for:)`, which
answers for one `LoadedExtension`, and `check(_:)`, which answers for a list
by running one `update(for:)` lookup per extension concurrently and folding
the results into an `ExtensionUpdateReport` (source:
`packages/apple/AgenticToolkit/Core/Extensions/ExtensionUpdateCheck.swift`). The contract's defining rule, stated in the type's own doc
comment, is that a newer version is reported only when
installing it would succeed: each candidate is run through the same
`OpenVSXExtensionDetail.installability(forHostVersion:)` gate the installer
uses, and a newer version that fails it is treated as no update at all, not
as an update the caller must separately refuse.

## Behavioral Requirements

- **default-client**: `ExtensionUpdateCheck.init` MUST default its `client`
  parameter to `OpenVSXClient()` when the caller supplies none.
- **default-host-version**: `ExtensionUpdateCheck.init` MUST default its
  `hostVersion` parameter to `ExtensionRegistry.declaredVSCodeVersion` when
  the caller supplies none.
- **publisher-required**: `update(for:)` MUST throw
  `ExtensionUpdateError.noPublisher(installed.identifier)` when
  `installed.manifest.publisher` is `nil` or the empty string, before making
  any registry request.
- **registry-lookup-by-manifest-fields**: `update(for:)` MUST request the
  registry's detail record by calling
  `client.detail(namespace: installed.manifest.publisher, name: installed.manifest.name)`,
  using the manifest's `publisher` and `name` fields verbatim rather than
  splitting `installed.identifier` (the case-folded `publisher.name` string)
  back apart, because a publisher name containing a `.` would split at the
  wrong place and the identifier's case-folding is this host's convention,
  not the registry's.
- **latest-version-requested**: `update(for:)` MUST call `client.detail`
  with no `version` argument, so the registry returns the latest published
  version rather than a specific one.
- **versions-must-both-parse**: `update(for:)` MUST throw
  `ExtensionUpdateError.versionNotComparable(installed: installed.manifest.version, published: latest.version)`
  when `SemanticVersion(installed.manifest.version)` is `nil`, when
  `latest.semanticVersion` is `nil`, or both.
- **no-downgrade-offered**: `update(for:)` MUST return `nil` when the parsed
  published version is not strictly greater than the parsed installed
  version — covering both an equal version and a published version that is
  older than what is installed (the version comparison and the doc comment on
  `ExtensionUpdateError.versionNotComparable`).
- **installability-gate**: `update(for:)` MUST return `nil`, and MUST NOT
  return an `ExtensionUpdate`, when
  `latest.installability(forHostVersion: hostVersion)` is not `.installable`,
  even though the published version is strictly newer than the installed one.
- **update-value-shape**: When a candidate is strictly newer and installable,
  `update(for:)` MUST return an `ExtensionUpdate` whose `identifier` is
  `installed.identifier`, whose `installedVersion` is
  `installed.manifest.version` (the raw string, not the parsed
  `SemanticVersion`), and whose `latest` is the full `OpenVSXExtensionDetail`
  the registry returned.
- **concurrent-per-extension-lookup**: `check(_:)` MUST run exactly one
  `outcome(for:)` lookup per element of `installed`, and MUST run every
  element's lookup concurrently rather than sequentially, using a
  `withTaskGroup` over one child task per extension.
- **per-lookup-failure-isolation**: `check(_:)` MUST NOT fail, throw, or omit
  results for the extensions whose lookup succeeded when one or more other
  extensions' lookups fail; a failed lookup MUST be represented as an entry
  in the returned report's `notCheckable` array rather than aborting the
  whole call (`outcome(for:)`'s internal `catch`).
- **check-never-throws**: `check(_:)` MUST be a non-throwing `async` function;
  every error `update(for:)` can raise, and any other error a registry
  request can raise, MUST be caught inside `outcome(for:)` and converted into
  an `ExtensionUpdateUnavailable` entry rather than propagated to `check(_:)`'s
  caller.
- **updates-sorted-by-identifier**: `check(_:)` MUST return
  `ExtensionUpdateReport.updates` sorted ascending by `identifier` using
  `String`'s default `<` operator, regardless of the order in which the
  concurrent lookups complete.
- **unavailable-sorted-by-identifier**: `check(_:)` MUST return
  `ExtensionUpdateReport.notCheckable` sorted ascending by `identifier` using
  `String`'s default `<` operator, regardless of the order in which the
  concurrent lookups complete.
- **empty-input-empty-report**: `check(_:)` MUST return an
  `ExtensionUpdateReport` with an empty `updates` array and an empty
  `notCheckable` array when `installed` is an empty array (no
  branch runs when the task group is given no tasks to add).
- **error-classification-not-published**: `outcome(for:)` MUST classify a
  caught error as `ExtensionUpdateUnavailable.Reason.notPublished` when, and
  only when, the error is `OpenVSXError.requestFailed(_, status: 404)`.
- **error-classification-no-publisher**: `outcome(for:)` MUST classify a
  caught error as `.noPublisher` when the error is
  `ExtensionUpdateError.noPublisher`.
- **error-classification-version-not-comparable**: `outcome(for:)` MUST
  classify a caught error as `.versionNotComparable` when the error is
  `ExtensionUpdateError.versionNotComparable`.
- **error-classification-default-unreachable**: `outcome(for:)` MUST
  classify every caught error that is not one of the three cases above —
  including every other `OpenVSXError` case (`requestFailed` with a status
  other than 404, `malformedRegistryURL`, `undecodableResponse`,
  `artifactNotFetchable`, `artifactTooLarge`, `unsafeIdentity`,
  `responseNotHTTP`, `responseTooLarge`) and any error of a type this
  component does not otherwise recognize — as
  `.registryUnreachable` (`default: return .registryUnreachable`).
- **failure-logged-at-debug**: `outcome(for:)` MUST log a `debug`-level
  message naming the failed extension's `identifier` and
  `String(describing: error)` for every caught error, before returning the
  `.notCheckable` outcome.
- **report-carries-both-arrays**: `ExtensionUpdateReport` MUST expose both
  `updates: [ExtensionUpdate]` and `notCheckable: [ExtensionUpdateUnavailable]`
  as separate arrays on every `check(_:)` result, so that "nothing to update"
  and "some extensions could not be asked about" remain distinguishable to a
  caller (doc comment).
- **value-type-equatability**: `ExtensionUpdate`, `ExtensionUpdateUnavailable`,
  `ExtensionUpdateUnavailable.Reason`, and `ExtensionUpdateReport` MUST each
  conform to `Equatable` and `Sendable`.
- **error-type-equatability**: `ExtensionUpdateError` MUST conform to `Error`,
  `Sendable`, and `Equatable`, with exactly two cases, `noPublisher(String)`
  and `versionNotComparable(installed: String, published: String)`.
- **non-sendable-lookup-result-type**: the private `ExtensionUpdateOutcome`
  enum used inside `check(_:)`'s task group MUST conform to `Sendable`, since
  it is the type parameter of `withTaskGroup(of:)` and is produced inside a
  concurrently-executing child task.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `client` | `OpenVSXClient` | `OpenVSXClient()` (the public Open VSX registry at `https://open-vsx.org/api`) | The registry client `update(for:)` and `check(_:)` issue lookups through; injected so tests can point it at a stub registry. |
| `hostVersion` | `SemanticVersion` | `ExtensionRegistry.declaredVSCodeVersion` (`1.138.0`) | The host version passed to `OpenVSXExtensionDetail.installability(forHostVersion:)` for every candidate; a caller who wants to check against a different declared version supplies it here. |
| `installed` | `[LoadedExtension]` | — (required parameter of `check(_:)`) | The extensions to check, one lookup per element; supplying `[]` is valid and yields an empty report. |

## Privacy

- **Data collected**: None persisted by this component. Per lookup,
  `update(for:)` reads the fields the caller's `LoadedExtension.manifest`
  already holds in memory — `publisher`, `name`, and `version` — and does
  not read or retain anything beyond those.
- **Storage**: Not applicable — `ExtensionUpdateCheck` and `OpenVSXClient`
  are documented as stateless and hold no cache (source doc comment on
  `OpenVSXClient`: "Stateless and `Sendable`... keeps no cache"); nothing is
  written to disk by this component.
- **Transmission**: Each `update(for:)` call discloses the installed
  extension's `publisher` (as the registry `namespace`) and `name` to
  whichever registry `client` addresses — the public
  `https://open-vsx.org/api` unless a caller configured a different
  `registryBase` — by placing them in the request path of
  `client.detail(namespace:name:)`. The installed `version`
  string is read locally for comparison but is never sent to the registry;
  only `namespace` and `name` appear in the outgoing request.
- **Retention**: Not applicable — no data from this component is retained
  beyond the single `update(for:)` or `check(_:)` call; `OpenVSXClient`
  itself caches nothing between calls.

