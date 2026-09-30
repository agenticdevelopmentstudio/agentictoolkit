<!-- leaf: implement-language/services--part-3 · source: language-services.md -->

# LanguageServices — continued (part 3)

**Rules** (cite as `implement-language/services--part-3#<slug>`):

- `scheduler-flushpendingsave-is-per-uri` MUST — flushPendingSave(uri:) MUST write only the named uri's pending save and MUST leave every other pending uri's debounce …
- `scheduler-flushpendingsave-no-double-write` MUST — two overlapping calls that both resolve to flushing the same uri — a second flushPendingSave(uri:), or one racing that …
- `scheduler-flushpendingsaves-reports-still-failing` MUST — flushPendingSaves() MUST attempt every pending uri's write, one at a time, and MUST return exactly the uris whose write …
- `scheduler-pendinguris-reflects-full-lifecycle` MUST — pendingURIs MUST list every uri that is scheduled, currently writing, or awaiting a backoff retry after a failed write.
- `scheduler-mainactor-isolation` MUST
- `documenturi-single-conversion-point` MUST — URL.documentUri MUST return absoluteString, and MUST be the one place in the framework a local file URL is converted to …

- **scheduler-flushPendingSave-is-per-uri**: `flushPendingSave(uri:)` MUST write only the named `uri`'s pending save and MUST leave every other pending `uri`'s debounce timer armed and untouched.
- **scheduler-flushPendingSave-no-double-write**: two overlapping calls that both resolve to flushing the same `uri` — a second `flushPendingSave(uri:)`, or one racing that `uri`'s debounce elapsing — MUST produce exactly one write; the later caller MUST await the write already in flight rather than starting a second one.
- **scheduler-flushPendingSaves-reports-still-failing**: `flushPendingSaves()` MUST attempt every pending `uri`'s write, one at a time, and MUST return exactly the `uri`s whose write is still pending once every attempt completes.
- **scheduler-pendingURIs-reflects-full-lifecycle**: `pendingURIs` MUST list every `uri` that is scheduled, currently writing, or awaiting a backoff retry after a failed write.
- **scheduler-mainactor-isolation**: `TextDocumentSaveScheduler` MUST be usable only from the main actor.
- **documentUri-single-conversion-point**: `URL.documentUri` MUST return `absoluteString`, and MUST be the one place in the framework a local file `URL` is converted to the `DocumentUri` (LSP's `file://` string form) it is opened under, so two independent call sites addressing "the same file" — the file editor opening a document, and the file tree looking that document back up to show a dirty indicator — read exactly the same string.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `uri` | `DocumentUri` (`String`) | none (required) | The document's identity throughout `TextDocument`, `TextDocumentStore`, and `TextDocumentSaveScheduler`; conventionally an LSP `file://` string produced by `URL.documentUri`. |
| `languageId` | `String` | none (required, `TextDocument.init`/`TextDocumentStore.open` only) | Passed through and stored verbatim; neither type validates or interprets it. |
| `text` | `String` | none (required, `TextDocument.init`/`TextDocumentStore.open` only) | The document's initial content; a duplicate `open` call's `text` is ignored (see `store-open-first-caller-authoritative`). |
| `version` | `Int` | `0` | `TextDocument.init`'s starting version; bumped by `apply(_:)` and `replaceAll(with:)` thereafter. |
| `debounce` | `Duration` | `.seconds(1)` | `TextDocumentSaveScheduler.init`'s per-key quiet period before a pending save runs. |
| `write` | `TextDocumentSaveScheduler.Write` (`@MainActor (TextDocument) async throws -> Void`) | none (required) | The caller-injected persistence closure; the scheduler decides only *when* it runs, never *how*. |
| `maximumRetryInterval` | `Duration` (internal `KeyedDebouncer` default) | `.seconds(30)` | Ceiling on the exponential backoff applied after a failed write; not exposed as a `TextDocumentSaveScheduler.init` parameter — a caller cannot currently override it without constructing its own `KeyedDebouncer`. |

## Privacy

- **Data collected**: `TextDocument` holds exactly the caller-supplied `text` for the file at `uri` — in practice, the full content of whatever file a user has open in an editor pane, plus that file's path (as a `DocumentUri`). Neither `TextDocument`, `TextDocumentStore`, nor `TextDocumentSaveScheduler` inspects, parses, or interprets that content beyond UTF-16 offset bookkeeping.
- **Storage**: held only in memory (`TextDocument.text`, and `TextDocumentStore`'s `documentsByURI` map) for as long as the document stays open; `TextDocumentSaveScheduler` writes it back to disk only through the caller-injected `write` closure, which this component does not implement — persistence, encryption, and location are entirely that closure's responsibility.
- **Transmission**: none of the four files performs any network call; each imports only `Foundation` (plus `LanguageServerProtocol` for shared LSP types, and `os` for logging in `TextDocumentSaveScheduler`).
- **Retention**: a document's text and dirty state persist in memory until `TextDocumentStore.close(uri:)` removes the last open reference to it; a save that keeps failing leaves its bytes only in memory, retried in the background with no time limit, until it succeeds or is explicitly `cancel`led.

## Platform Notes

- **SwiftUI**: not a dependency of any of the four files — each imports only `Foundation` (plus `LanguageServerProtocol`, and `os` for the scheduler's logger). A SwiftUI editor view consumes `TextDocument`/`TextDocumentStore`/`TextDocumentSaveScheduler` through injected instances and its own `@State`/`@Observable` wiring around the change/dirty-state handler tokens, not through anything this component provides directly.
- **AppKit / UIKit**: this is the source. All four files live in `packages/apple/AgenticToolkit/Language/`, part of the `AgenticToolkitLanguage` framework target (`project.yml` declares `platform: macOS`, no iOS target today), depending on `AgenticToolkitCore`, `JSONRPC`, `LanguageServerProtocol`, and `LanguageClient`. None imports AppKit or UIKit, so the type is equally usable from the headless daemon process or a windowed host.
- **Compose**: Kotlin's `String` is UTF-16-backed like Swift's, so `TextDocument`'s offset/`Position` math (including the surrogate-pair and CRLF boundary rounding) ports with direct code-unit arithmetic over `CharSequence`, not a `codePoint`-aware API. Model the refcounted registry as a class holding a `MutableMap<String, Entry>` confined to a single `CoroutineDispatcher` (the direct analogue of `@MainActor`), and port `TextDocumentSaveScheduler`/`KeyedDebouncer` as a `Job`-per-key debounce (`launch { delay(debounceMs) }`) with the same generation-bump-on-reschedule and exponential-backoff-on-failure bookkeeping, since Kotlin coroutines offer no built-in debounce-with-retry primitive.
- **React/Web**: JavaScript strings are UTF-16 internally (`String.prototype.length`/`charCodeAt` already operate on UTF-16 code units), so the offset/position math ports almost unchanged. Model the debounced autosave with a `Map<uri, { timer, generation, failures }>` and `setTimeout`/`clearTimeout` in place of `KeyedDebouncer`'s `Task`-based timers, and the refcounted store as a `Map<string, { document, openCount }>`; persistence goes through the File System Access API or a backend endpoint, wrapped in the same never-remove-on-failure retry loop.
- **WinUI 3**: .NET's `System.String` is also UTF-16 (`Length`/the string indexer are UTF-16 code units, matching Swift's `text.utf16`), so `TextDocument`'s offset/`Position` conversion, including surrogate-pair and CRLF boundary rounding, ports with direct index arithmetic and no encoding translation. Model `TextDocumentStore`'s refcounted registry as a `Dictionary<string, Entry>` confined to the UI thread's `DispatcherQueue` (the closest analogue to `@MainActor`), and port `TextDocumentSaveScheduler`/`KeyedDebouncer` with a `DispatcherQueueTimer` or `Task.Delay`-based per-key debounce that keeps a failed key's entry — mirroring `retry-ceiling-default-and-floor`-style backoff — until a write via `System.IO.File.WriteAllTextAsync` succeeds or is explicitly cancelled.

