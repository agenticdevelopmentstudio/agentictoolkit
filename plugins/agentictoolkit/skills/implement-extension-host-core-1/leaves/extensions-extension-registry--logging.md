<!-- leaf: implement-extension-host-core-1/extensions-extension-registry--logging · source: extension-host-core-extensions-extension-registry.md -->

# Extension Registry

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (falls back to `"nil"` if unset, via the shared `Loggable` protocol) | Category: `ExtensionRegistry`

| Event | Level | Message |
|-------|-------|---------|
| A directory's manifest decodes, passes the engine gate, and claims a fresh identifier | info | `Loaded extension '<identifier>' from <directory path>` |
| Any recorded `ExtensionLoadError` (`manifestUnreadable`, `manifestMalformed`, `engineRangeUnparsable`, `engineIncompatible`, `contributionPointFailed`) | warning | `Failed to load extension at <directory path>: <reason>` |
| A second directory claims an identifier an earlier directory already loaded | warning | `Skipping duplicate extension '<identifier>' at <directory path>; already loaded from <existing path>` |
| A registered `ContributionPoint`'s `apply` throws for a loaded extension | error | `Contribution point '<contributionKey>' failed to apply '<identifier>': <error description>` |
| A `reload(performing:)` call's scan result is discarded because a later `reload` began and finished first | debug | `Dropping the result of reload <generation>: superseded by <current generation> while it was scanning.` |
