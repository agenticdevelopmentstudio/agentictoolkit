<!-- leaf: implement-extension-host-core-1/extensions-vsix-archive · source: extension-host-core-extensions-vsix-archive.md -->

# VSIXArchive

## Overview

`VSIXArchive` is a stateless namespace `enum` with two public operations on a
downloaded `.vsix` file: `verify`, which checks the raw archive bytes against
whatever digest and Ed25519 signature the registry published for them, and
`expand`, which unpacks the archive onto disk through the platform's own
`ditto` unarchiver under a timeout and a decompressed-size ceiling (source:
doc comment on `VSIXArchive`). A `.vsix` is a zip whose extension
tree lives under an `extension/` subdirectory alongside packaging metadata
this host does not read; `payloadDirectory(in:)` is the one place that
subdirectory name is spelled out.

Both operations are read-only with respect to the network: nothing here
downloads anything. The one caller in this codebase,
`packages/apple/AgenticToolkit/Core/Extensions/VSIXInstaller.swift`, fetches
the archive bytes and the optional digest/signature/key text over HTTP
itself, then calls `VSIXArchive.verify` followed by `VSIXArchive.expand`
synchronously, inside a dedicated blocking-work context, because neither
function suspends and both can hold a thread for the length of a 512 MB
download's worth of hashing or a `ditto` run (`VSIXInstaller.swift`).

`verify`'s doc comment states plainly what its two checks do and do not
establish: the digest and signature are both checked against values the
*registry* published in the same response that named the archive, never
against an out-of-band publisher key, so a registry serving altered bytes
under a key of its own passes every check here. That is why a fully verified
result is named `.registryAttested` rather than `.verified`.

## Behavioral Requirements

All line references below are to
`packages/apple/AgenticToolkit/Core/Extensions/VSIXArchive.swift` unless
another file is named.
