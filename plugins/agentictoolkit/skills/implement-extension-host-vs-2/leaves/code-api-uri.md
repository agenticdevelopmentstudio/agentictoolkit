<!-- leaf: implement-extension-host-vs-2/code-api-uri · source: extension-host-vs-code-api-uri.md -->

# Uri

## Overview

`Uri.swift` is an `extension VSCodeAPI` (`VSCodeAPI` is the `@MainActor public enum` every `vscode.*` adaptor installs through) holding the JavaScript `vscode.Uri` class and the Swift-facing bridge built on it. `installUriClass(in:)` evaluates a single ES5 source string (`uriClassSource`) that builds a real JavaScript constructor function — `scheme`/`authority`/`path`/`query`/`fragment`/`fsPath` as frozen prototype getters, `with`/`toString`/`toJSON` as prototype methods, `Uri.file`/`Uri.parse`/`Uri.joinPath` as static methods — and caches the result under a non-enumerable global so every context builds the class at most once. `url(from:in:)` reads a `URL` out of a JavaScript value that is either a real `Uri` instance or a plain string, the two shapes VS Code's own API accepts wherever it documents a `Uri | string` parameter, answering `nil` for anything else without raising. `uriValue(for:in:)` is the reverse: it builds a `vscode.Uri` instance for a Swift `URL` by calling `Uri.parse(url.absoluteString)`. The class is deliberately narrower than real VS Code's `Uri` in five stated ways (POSIX-only paths, `path` kept percent-encoded while `fsPath` is decoded, `query`/`fragment` never decoded except by `toString(true)`, `strict` checking only that a scheme is present, and `joinPath` collapsing duplicate `/` without resolving `.`/`..`); see Design Decisions.

