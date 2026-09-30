<!-- leaf: implement-extension-host-core-1/extensions-vsix-installer · source: extension-host-core-extensions-vsix-installer.md -->

# VSIXInstaller

## Overview

`VSIXInstaller` is a `Sendable` `struct` that puts a `.vsix` on disk as a
directory `ExtensionRegistry` can load, and takes the previous install of the
same extension away in the same step. Its whole design is organized around
two states a half-done install would leave behind, both worse than an outright
failure: a partly written directory (`ExtensionRegistry.load(from:)` silently
skips a folder whose `package.json` has not landed yet, calls the scan
complete anyway, and then prunes that extension's themes as orphans — the
user's selected theme does not come back), and two directories claiming one
identifier (the registry resolves that by sorted directory name, which is not
version order, so `…-1.10.0` sorting before `…-1.9.0` can leave an *old*
version winning after an update that only added a folder).

It has two public entry points that converge on one code path. `install(_:
using:)` is the registry half: it decides installability and verification
completeness from `OpenVSXExtensionDetail` metadata alone, downloads the
archive and whichever verification artifacts the registry named, then hops
off the cooperative thread pool to hash and check the archive and write it to
disk. `install(archive:verification:expectedIdentifier:source:)` is the local
half — what a user dropping a `.vsix` on the app reaches directly, and what
the registry half calls once it already has proved bytes in hand. Every
identity and containment check downstream of the manifest applies on both
paths alike, because the manifest is a document neither a registry response
nor a user's file selection can be trusted to agree with.

All line references below are to
`packages/apple/AgenticToolkit/Core/Extensions/VSIXInstaller.swift` unless
another file is named.

