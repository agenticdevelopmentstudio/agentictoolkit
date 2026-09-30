<!-- leaf: implement-extension-host-core-1/extensions-extension-manifest · source: extension-host-core-extensions-extension-manifest.md -->

# ExtensionManifest

## Overview

`ExtensionManifest` is the `Codable` model of a VS Code `package.json` inside
`AgenticToolkitCore` (`packages/apple/AgenticToolkit/Core/Extensions/ExtensionManifest.swift`,
a macOS-only framework target per `project.yml`). It has no visual surface of
its own: it is a pure, synchronous decode/encode layer — everything Stage 4c
and Stages 5-7 of the extension host read to install themes, snippets,
languages, commands, keybindings, menus, settings, views, view containers,
and (later) language-model tools comes from the `Contributions` value this
type decodes. Its defining discipline is asymmetric strictness: `name`,
`version`, `engines.vscode`, and `contributes`'s own shape are the
extension's non-negotiable identity, and a manifest missing or misspelling
any of them fails to decode entirely; everything else — every
`contributes.*` array element, every keyed-dictionary location, every
optional scalar field — is decoded with element- or field-level isolation,
so one malformed theme, command, or configuration property never costs its
siblings. A companion `LenientDecoding` helper implements that isolation
once, shared by every `contributes.*` collection, and a typed
`DecodingFailure` record — never itself re-encoded — is how a caller learns
what, if anything, one decode attempt had to drop.

