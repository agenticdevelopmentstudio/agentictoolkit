<!-- leaf: implement-extension-host-core-1/extensions-open-vsx-catalog · source: extension-host-core-extensions-open-vsx-catalog.md -->

**Rules** (cite as `implement-extension-host-core-1/extensions-open-vsx-catalog#<slug>`):

- `url-shaped-fields-decoded-as-string` MUST
- `search-entry-identifier-case-folded` MUST
- `search-entry-icon-url-resolves-independently` MUST
- `search-page-total-size-is-whole-result-set` MUST
- `search-page-array-decode-is-all-or-nothing` MUST
- `extension-detail-identifier-case-folded` MUST
- `license-field-carries-absence` MUST
- `semantic-version-nil-on-non-semver` MUST
- `engine-range-nil-when-absent-or-unparseable` MUST
- `universal-download-is-the-only-download-url-exposed` MUST
- `file-urls-resolve-per-named-key` MUST
- `web-extension-kind-is-advisory-only` MUST
- `installability-checks-platform-before-download-existence` MUST
- `installability-requires-a-universal-download` MUST
- `installability-engine-gate-skipped-when-absent-or-empty` MUST
- `installability-engine-range-unreadable-carries-raw-string` MUST
- `installability-engine-incompatible-carries-parsed-range` MUST
- `installability-default-is-installable` MUST
- `installability-is-pure-and-synchronous` MUST
- `is-installable-reflects-only-the-installable-case` MUST
- `installability-refusal-cases-are-named-not-freeform` MUST
- `catalog-types-are-sendable-value-types` MUST

# OpenVSXCatalog

## Overview

`OpenVSXCatalog.swift` (`packages/apple/AgenticToolkit/Core/Extensions/OpenVSXCatalog.swift`,
inside the macOS-only `AgenticToolkitCore` framework target per `project.yml`)
is the `Codable` model of what the Open VSX registry's HTTP API returns: one
summary row from `GET /api/-/search` (`OpenVSXSearchEntry`), one page of that
search (`OpenVSXSearchPage`), and the full record for one version of one
extension from `GET /api/<namespace>/<name>` or `.../<version>`
(`OpenVSXExtensionDetail`). It has no visual surface, performs no network
request itself, and is not the code that fetches these responses — that is
`OpenVSXClient.swift`, out of this recipe's scope. Its defining discipline is
that every URL-shaped registry field decodes as `String`, never `URL`, so
that one entry with a malformed icon link never sinks the decode of the page
it appeared on; computed accessors parse each URL lazily, where it is used, so
a bad string costs exactly the accessor that reads it. The file's second job
is `OpenVSXExtensionDetail.installability(forHostVersion:)`, a pure function
from already-decoded metadata to a named `OpenVSXInstallability` verdict —
whether a given registry version could be installed into this host at all,
decided before any bytes are downloaded.

## Behavioral Requirements

- **url-shaped-fields-decoded-as-string**: `OpenVSXSearchEntry.files`,
  `OpenVSXExtensionDetail.downloads`, and `OpenVSXExtensionDetail.files` MUST
  decode as `[String: String]?`, never as a dictionary of `URL`, so a value
  that cannot parse as a URL costs only the computed accessor that reads it
  and never the decode of the entry or the page containing it.
- **search-entry-identifier-case-folded**: `OpenVSXSearchEntry.identifier`
  MUST return `` "\(namespace).\(name)".lowercased() ``.
- **search-entry-icon-url-resolves-independently**:
  `OpenVSXSearchEntry.iconURL` MUST return the parsed `URL` when
  `files["icon"]` is present and parseable, and MUST return `nil`, never
  throw, when the key is absent or the string is unparseable.
- **search-page-total-size-is-whole-result-set**:
  `OpenVSXSearchPage.totalSize` MUST report the size of the entire result set
  the query matched, not the number of elements in that page's `extensions`
  array, so a caller can decide whether to request another `offset`.
- **search-page-array-decode-is-all-or-nothing**:
  `OpenVSXSearchPage.extensions` MUST decode via `Decodable`'s synthesized
  array decoding, which MUST throw for the whole page when any one element is
  missing a required field (`namespace`, `name`, or `version`) or gives it
  the wrong JSON type — this file implements no per-element recovery for
  `OpenVSXSearchEntry` the way it does for a single URL-shaped field (48-52; contrast with **url-shaped-fields-decoded-as-string**).
- **extension-detail-identifier-case-folded**:
  `OpenVSXExtensionDetail.identifier` MUST return
  `` "\(namespace).\(name)".lowercased() `` and, for the same `namespace` and
  `name`, MUST equal `OpenVSXSearchEntry.identifier`, so a search row and a
  detail record for the same extension join without either side re-deriving
  the case-folding rule (see **search-entry-identifier-case-folded**).
- **license-field-carries-absence**: `OpenVSXExtensionDetail.license` MUST
  decode to `nil` when the `license` key is absent, and MUST preserve
  whatever string the registry sent verbatim — including an empty string —
  when the key is present, with no normalization between the two.
- **semantic-version-nil-on-non-semver**:
  `OpenVSXExtensionDetail.semanticVersion` MUST return `nil`, never throw or
  substitute a default, when `version` does not parse as `SemanticVersion`.
- **engine-range-nil-when-absent-or-unparseable**:
  `OpenVSXExtensionDetail.engineRange` MUST return `nil` both when `engines`
  is absent or has no `vscode` key, and when the `vscode` value is present
  but does not parse as `VSCodeEngineRange`, drawing no distinction between
  those two cases at this property; the distinction between "not gated" and
  "unreadable" is drawn only by `installability(forHostVersion:)`.
- **universal-download-is-the-only-download-url-exposed**:
  `OpenVSXExtensionDetail.universalDownloadURL` MUST return the parsed URL
  for `downloads["universal"]` only, and MUST return `nil` when that key is
  absent, even when `downloads` holds one or more other platform-keyed
  entries.
- **file-urls-resolve-per-named-key**: `sha256URL`, `signatureURL`,
  `publicKeyURL`, `licenseTextURL`, `readmeURL`, and `iconURL` on
  `OpenVSXExtensionDetail` MUST each resolve independently through the
  shared `fileURL(_:)` helper reading `files[key]`, and MUST each return
  `nil` on its own — with no effect on any other accessor — when its own key
  is absent or its value is unparseable.
- **web-extension-kind-is-advisory-only**: `declaresWebExtensionKind` MUST
  report whether the registry's `extensionKind` array contains the string
  `"web"`, and `installability(forHostVersion:)` MUST NOT read
  `extensionKind` or `declaresWebExtensionKind` at all when computing its
  verdict.
- **installability-checks-platform-before-download-existence**:
  `installability(forHostVersion:)` MUST return `.platformSpecific(platform)`
  when `targetPlatform` is present and not equal to the literal string
  `"universal"`, and MUST perform this check before checking whether a
  universal download exists.
- **installability-requires-a-universal-download**:
  `installability(forHostVersion:)` MUST return `.noUniversalBuild` when
  `universalDownloadURL` is `nil`, checked after the platform check and
  before any engine check.
- **installability-engine-gate-skipped-when-absent-or-empty**:
  `installability(forHostVersion:)` MUST treat a `nil` `engines["vscode"]`
  and an empty-string `engines["vscode"]` identically: both MUST skip the
  engine check entirely rather than being treated as an unparseable range.
- **installability-engine-range-unreadable-carries-raw-string**:
  `installability(forHostVersion:)` MUST return
  `.engineRangeUnreadable(declared)`, carrying the exact `engines["vscode"]`
  string, when that string is non-empty and does not parse as
  `VSCodeEngineRange`.
- **installability-engine-incompatible-carries-parsed-range**:
  `installability(forHostVersion:)` MUST return `.engineIncompatible(range)`,
  carrying the parsed `VSCodeEngineRange`, when the range parses but
  `range.accepts(host)` is `false`.
- **installability-default-is-installable**:
  `installability(forHostVersion:)` MUST return `.installable` when the
  platform check, the download-existence check, and the engine check (when
  applicable) all pass.
- **installability-is-pure-and-synchronous**:
  `installability(forHostVersion:)` MUST compute its result solely from
  `self`'s already-decoded fields and the `host` argument, MUST return
  synchronously, and MUST NOT perform file, network, or process access.
- **is-installable-reflects-only-the-installable-case**:
  `OpenVSXInstallability.isInstallable` MUST return `true` if and only if the
  value equals `.installable`, and MUST return `false` for every other case.
- **installability-refusal-cases-are-named-not-freeform**:
  `OpenVSXInstallability` MUST expose one distinct case per refusal reason
  (`engineIncompatible`, `engineRangeUnreadable`, `platformSpecific`,
  `noUniversalBuild`) rather than a `Bool` paired with a freeform message, so
  a caller can distinguish and separately present each reason without
  parsing prose.
- **catalog-types-are-sendable-value-types**: `OpenVSXSearchEntry`,
  `OpenVSXSearchPage`, `OpenVSXExtensionDetail`, and `OpenVSXInstallability`
  MUST each be declared `Sendable` and `Equatable` value types with no
  `actor` or `@MainActor` isolation, and decoding MUST be a synchronous,
  side-effect-free function of the `Decoder` handed to it, so a decoded
  value MAY be passed freely across concurrency domains and MAY be decoded
  concurrently by independent callers with no external coordination.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| JSON payload | `Data` (via a `Decoder`) | none — required | The sole decode input for `OpenVSXSearchEntry`, `OpenVSXSearchPage`, and `OpenVSXExtensionDetail`; a caller constructs its own `JSONDecoder()` and calls `.decode(_:from:)` — this file defines no custom `keyDecodingStrategy` or `userInfo`. |
| `host` | `SemanticVersion` | none — required | The caller-supplied host version `installability(forHostVersion:)` compares a declared `engines.vscode` range against. |

No environment variable, settings key, or injected dependency exists
anywhere in this file. `Self.universalTargetPlatform` (the literal string
`"universal"`) is a fixed, compile-time constant read by two properties and
one check — it is not runtime configuration a caller can vary.

