<!-- leaf: implement-language/services · source: language-services.md -->

# LanguageServices

## Overview

`LanguageServices` is the Foundation-only, `@MainActor` core behind every LSP-backed editor pane in `packages/apple/AgenticToolkit/Language/`: `TextDocument` (one open file's URI, language id, monotonically increasing version, text, and dirty flag, with a cached line index for UTF-16 offset/`Position` conversion), `TextDocumentStore` (the reference-counted registry of currently-open `TextDocument`s, shared by every editor pane so two panes on the same file share one buffer), `TextDocumentSaveScheduler` (a per-URI debounced autosave that never drops a failed write), and `URL.documentUri` (the single conversion from a local file `URL` to the `DocumentUri` string two independent call sites must agree on). None of the four imports AppKit, UIKit, or SwiftUI, so the whole surface is usable from the headless daemon process as well as from a windowed host. LSP addresses text in UTF-16 code units, not `Character`s or bytes — `TextDocument` is built around that fact, including the emoji-and-accented-character-counts-as-more-than-one-unit consequence of it. `TextDocumentSaveScheduler` wraps `KeyedDebouncer<DocumentUri>` (`Core/Concurrency/KeyedDebouncer.swift`), a generic per-key debounce-and-retry helper this file depends on but does not define.

