<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-diagnostics--part-4 · source: extension-host-vs-code-api-main-thread-diagnostics.md -->

# MainThreadDiagnostics — continued (part 4)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `store` | `ExtensionDiagnosticStore` | none (required) | `MainThreadDiagnostics.init`'s storage seam; MAY be shared across multiple adaptors, each tracking only its own `ownedOwners`. |
| `sink` | `ExtensionDiagnosticSink` | none (required) | Notified of every mutation's affected `URL`s; production passes `HostDiagnosticSink`. |
| `events` | `ExtensionEventEmitter<[URL]>` | none (required) | The shared emitter behind `onDidChangeDiagnostics`; built via `makeOnDidChangeDiagnosticsEmitter(window:)` and handed to every adaptor and to the sink alike. |
| `window` (to `makeOnDidChangeDiagnosticsEmitter`) | `ExtensionEventWindowScheduling` | none (required) | The debounce window scheduler; production passes `ExtensionEventTimerWindow()`. |
| `name` (to `createDiagnosticCollection`) | JS string, `undefined`, or `null` | generated `_generated_diagnostic_collection_name_#<n>` when omitted | The collection's requested name; MAY collide with an existing one (see **collection-name-collision-keeps-name-uniquifies-owner**). |
| `VSCodeAPI.maximumDecodableArrayLength` | `Int` | `100_000` | Declared in `VSCodeAPI.swift`; the ceiling `VSCodeAPI.arrayLength(of:)` enforces for `diagnosticArray`/`setEntriesArray`. Not settable per call. |
| `onDidChangeDiagnosticsDelay` | `TimeInterval` | `0.050` | The debounce window width; a `static let`, not configurable per instance. |

## Localization

- **hardcoded-error-messages**: every `TypeError`/`Error` message this file raises — `"createDiagnosticCollection requires a string name, or no argument."`, `"getDiagnostics requires a Uri, or no argument."`, `"Could not decode a diagnostic for this Uri."`, `"Could not decode a diagnostic entry."`, `"Invalid entries passed to DiagnosticCollection.set."`, `"DiagnosticCollection.set requires a Uri, an entries array, or no argument."`, `"Invalid diagnostics array passed to DiagnosticCollection.set."`, `"DiagnosticCollection.delete requires a Uri."`, `"DiagnosticCollection.get requires a Uri."`, `"DiagnosticCollection.has requires a Uri."`, `"DiagnosticCollection.forEach requires a callback function."`, `"DiagnosticCollection.forEach could not decode the Uri of an entry."`, `"DiagnosticCollection.forEach could not decode a diagnostic for this Uri."`, and `"DiagnosticCollection.forEach could not invoke its callback."` — are hardcoded English string literals with no localization key or `String(localized:)` call. They are visible to the extension author that made the mistake, not to the app's own end-user UI.
- **hardcoded-log-strings**: this file itself calls `logger` nowhere directly (it declares `Loggable` conformance only); the one logging event a call into this file's decode paths can trigger — `VSCodeAPI.arrayLength(of:)`'s `"refusing an array of <count> elements: longer than the 100000 this host decodes"` — is a hardcoded, unlocalized `Logger` interpolated string declared in `VSCodeAPI.swift`, shared by every `VSCodeAPI` extension file including this one.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `createDiagnosticCollection requires a string name, or no argument.` | `handleCreateDiagnosticCollection`, thrown when the first argument is present, not a string, and not `undefined`/`null`. |
| (none — literal only) | `getDiagnostics requires a Uri, or no argument.` | `handleGetDiagnostics`, thrown when a present, non-`null` first argument does not decode as a `Uri`. |
| (none — literal only) | `Could not decode a diagnostic for this Uri.` | `handleGetDiagnostics`'s resource branch and `handleCollectionGet`, thrown when a stored diagnostic fails to re-encode. |
| (none — literal only) | `Could not decode a diagnostic entry.` | `handleGetDiagnostics`'s no-argument branch and `pairsArrayValue`, thrown when a stored pair fails to re-encode. |
| (none — literal only) | `Invalid entries passed to DiagnosticCollection.set.` | `handleCollectionSet`, thrown when the array-taking overload's argument contains an undecodable tuple. |
| (none — literal only) | `DiagnosticCollection.set requires a Uri, an entries array, or no argument.` | `handleCollectionSet`, thrown when the first argument is truthy, not an array, and not a `Uri`. |
| (none — literal only) | `Invalid diagnostics array passed to DiagnosticCollection.set.` | `handleCollectionSet`, thrown when the single-`Uri` overload's second argument is present but not decodable. |
| (none — literal only) | `DiagnosticCollection.delete requires a Uri.` | `handleCollectionDelete`, thrown on a missing/undecodable first argument. |
| (none — literal only) | `DiagnosticCollection.get requires a Uri.` | `handleCollectionGet`, thrown on a missing/undecodable first argument. |
| (none — literal only) | `DiagnosticCollection.has requires a Uri.` | `handleCollectionHas`, thrown on a missing/undecodable first argument. |
| (none — literal only) | `DiagnosticCollection.forEach requires a callback function.` | `handleCollectionForEach`, thrown when the first argument is not `instanceof Function`. |
| (none — literal only) | `DiagnosticCollection.forEach could not decode the Uri of an entry.` | `handleCollectionForEach`, thrown when an entry's stored `Uri` fails to re-encode. |
| (none — literal only) | `DiagnosticCollection.forEach could not decode a diagnostic for this Uri.` | `handleCollectionForEach`, thrown when an entry's diagnostics fail to re-encode. |
| (none — literal only) | `DiagnosticCollection.forEach could not invoke its callback.` | `handleCollectionForEach`, thrown when `VSCodeAPI.call` reports `.unavailable`. |
| (none — literal only) | `refusing an array of <count> elements: longer than the 100000 this host decodes` | Logged inside `VSCodeAPI.swift`'s shared `arrayLength(of:)`, not inside this file; reached via `diagnosticArray`/`setEntriesArray`. |

## Privacy

- **Data collected**: `MainThreadDiagnostics.swift` collects no data of its own; it stores and re-encodes whatever `Uri`, `Diagnostic` (range, message, severity, source, code, relatedInformation, tags), and collection-name values an extension supplies through `vscode.languages` calls, without retaining a copy beyond `ExtensionDiagnosticStore`'s own in-memory state for the lifetime of the collections that hold them.
- **Storage**: all state lives in `ExtensionDiagnosticStore`'s in-memory `collections`/`ownerOrder`; nothing in this file persists to disk, `UserDefaults`, or any other durable store.
- **Transmission**: this file makes no network call; it neither sends nor receives anything over a network.
- **Retention**: a collection's diagnostics are retained only until that collection's own `dispose()` or the owning adaptor's `dispose()` removes it from `store`; nothing here retains data beyond that lifetime, and a torn-down adaptor's collections are actively removed rather than merely dereferenced.

