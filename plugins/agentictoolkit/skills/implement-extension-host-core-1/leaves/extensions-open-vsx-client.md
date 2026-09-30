<!-- leaf: implement-extension-host-core-1/extensions-open-vsx-client · source: extension-host-core-extensions-open-vsx-client.md -->

# OpenVSXClient

## Overview

`OpenVSXClient` is a stateless, `Sendable` `struct` that reads the Open VSX
extension registry over HTTPS: one page of catalog search results, the full
metadata record for one extension version, and the raw bytes or trimmed text
of a registry-named artifact (a `.vsix`, its detached `.sigzip` signature
archive, its `.sha256` digest, or its public key). It is read-only by
construction — there is no publish, review, or account surface on this type,
and nothing it sends to the registry beyond the request itself could be
attributed to a user (source: doc comment on `OpenVSXClient`).
It holds no cache: every call re-fetches from the registry, because a
memoizing client would hand an update check a stale "latest version" when
being current is the whole point of the check (doc comment).

Callers reach it to browse and vet an extension before installing it — the
doc comment on `detail` names `ExtensionUpdateCheck`, which feeds a
sideloaded extension's manifest `publisher` field in as `namespace`, and the
doc comment on the private `requireSafeComponent` helper names `VSIXInstaller`
as the sibling caller that applies the same identity guard to the same kind
of manifest field before building an install directory name. `OpenVSXClient` itself never touches the filesystem and
never installs anything; it only hands back registry-published bytes and
metadata, safely, to whichever caller does.

All line references below are to
`packages/apple/AgenticToolkit/Core/Extensions/OpenVSXClient.swift` unless
another file is named.

