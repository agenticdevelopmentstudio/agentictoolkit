<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-tree-views--part-4 · source: extension-host-vs-code-api-main-thread-tree-views.md -->

# MainThreadTreeViews — continued (part 4)

**Rules** (cite as `implement-extension-host-vs-1/code-api-main-thread-tree-views--part-4#<slug>`):

- `hastreedataprovider-and-treedatasource-answer-false-nil-when-disposed` MUST
- `logging-conformance` MUST
- `winui-3` MUST — model ExtensionTreeModel's element table as a class whose every member runs on a captured DispatcherQueue (the …

- **hastreedataprovider-and-treedatasource-answer-false-nil-when-disposed**: `hasTreeDataProvider(for:)` MUST return `false` and `treeDataSource(for:)` MUST return `nil` whenever `MainThreadTreeViews.isDisposed` is `true`, regardless of whether `models` still holds an entry for the given view id.
- **logging-conformance**: both `MainThreadTreeViews` and `ExtensionTreeModel` MUST conform to `Loggable`, each exposing its own `nonisolated static let logger` built with `makeLogger()`.

`forgetDescendants(of:)` is declared on `ExtensionTreeModel` but is not called anywhere in this file; the targeted-refresh diff in `items(from:parentHandle:in:)` (**targeted-refresh-forgets-only-genuinely-removed-children**) is what actually retires a handle's descendants today. This is a fact about the current source, not a gap — `forget(_:)` (which `forgetDescendants` itself is built on) is what every live code path calls.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `notImplementedLedger` | `NotImplementedLedger` | none (required) | Shared record of unimplemented `vscode` members this extension reached for; passed to every `ExtensionTreeModel` this adaptor creates. |
| `extensionIdentifier` | `String` | none (required) | The extension this adaptor instance belongs to; attributed on every ledger row and every log line. |
| `commands` | `CommandRegistry` | none (required) | The registry `activate(_:)` dispatches a row's declared command through. |
| `TreeViewOptions.canSelectMany` | `Bool` | `false` | Read by `readOptions`; sets `ExtensionTreeModel.allowsMultipleSelection`. |
| `TreeViewOptions.showCollapseAll` | `Bool` | `false` | Read by `readOptions`; `true` records a not-implemented ledger row and has no other effect. |
| `TreeViewOptions.dragAndDropController` | object | absent | Read by `readOptions`; presence records a not-implemented ledger row and has no other effect. |
| `TreeViewOptions.manageCheckboxStateManually` | `Bool` | `false` | Read by `readOptions`; `true` records a not-implemented ledger row and has no other effect. |

## Localization

`MainThreadTreeViews` raises with hardcoded English string literals; none carries a localization key, `String(localized:)` call, or String Catalog entry. Every raised message reaches the extension as a thrown JavaScript error, so an extension author sees the literal English text regardless of locale. The log-only messages (`ExtensionTreeModel.log`, the duplicate-registration warning, the dropped-duplicate-handle warning) reach only the host's own log, never the extension.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `<path>'s first argument must be a view id string.` | Raised by `registerTreeDataProvider` or `createTreeView` when the first argument is missing or not a string. |
| (none — literal only) | `<path>'s second argument must be a TreeViewOptions object.` | Raised by `createTreeView` when the second argument is missing or not an object. |
| (none — literal only) | `<path> requires a TreeDataProvider with getChildren(element) and getTreeItem(element) methods.` | Raised by either member when the provider argument fails **provider-requires-getchildren-and-gettreeitem**. |
| (none — literal only) | `<path> is unavailable: this extension's host has been torn down.` | Raised by either member when `isDisposed` is `true`. |

## Privacy

- **Data collected**: `MainThreadTreeViews`/`ExtensionTreeModel` collect no data of their own; `elements`, `commandsByHandle`, `parentByHandle`, and `childHandles` hold, for the lifetime of each registration, `JSValue`s and identifiers the extension itself supplied (and, indirectly through them, the `JSContext` and everything the extension's module graph captured). `NotImplementedLedger` (out of this file's scope) retains the extension identifier and member path of every not-implemented member reached for.
- **Storage**: `MainThreadTreeViews`/`ExtensionTreeModel` perform no storage of their own; every table here is in-memory only and exists for the registration's lifetime.
- **Transmission**: nothing here leaves the process; every call is an in-process JavaScriptCore round trip between the host and a `JSContext` the same process owns.
- **Retention**: a registration's `JSValue`s (elements, the provider, the change subscription) are retained until `invalidate()` runs — via a superseding registration (**provider-replacement-ordering**), an explicit `Disposable` call, the `TreeView` object's `dispose` member, or `MainThreadTreeViews.dispose()` — per **invalidate-is-idempotent-and-releases-the-change-subscription**.

## Platform Notes

- **SwiftUI**: not applicable to this file — `MainThreadTreeViews.swift` imports only `Foundation`, `JavaScriptCore`, `os`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing in this component renders a view.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadTreeViews.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is `@MainActor`-isolated per both class declarations, and its one given caller-side collaborator, `ExtensionTreeViewController` (`agentictoolkit://recipes/extension-tree-view-controller`), is an `NSOutlineView`-backed macOS controller.
- **Compose**: model `MainThreadTreeViews` as a Kotlin class holding a `MutableMap<String, ExtensionTreeModel>`, confined to the main dispatcher to mirror `@MainActor`. `ExtensionTreeModel`'s `elements`/`commandsByHandle`/`parentByHandle`/`childHandles` become plain `MutableMap`s guarded by that same confinement (no `Mutex` needed, matching the source's own single-actor argument); the four `ExtensionEventEmitter`s become `SharedFlow`s a `TreeView`-equivalent surface collects from, matching how `agentictoolkit://recipes/extension-host-vs-code-api-extension-tree-data-source` already models that boundary.
- **React/Web**: this component's own upstream is VS Code's real `MainThreadTreeViews` (`mainThreadTreeViews.ts`), already TypeScript, so a web port is closer to restoring the original than translating it — a class wrapping the same element-handle bookkeeping, with `registerTreeDataProvider` returning a `Disposable`-shaped object and `createTreeView` returning a plain object exposing native `EventEmitter`s instead of this file's hand-built `ExtensionEventEmitter` bridge.
- **WinUI 3**: model `ExtensionTreeModel`'s element table as a class whose every member runs on a captured `DispatcherQueue` (the `@MainActor` equivalent — WinUI 3 has no compiler-enforced actor isolation, so every entry point MUST assert `DispatcherQueue.HasThreadAccess` or marshal via `DispatcherQueue.TryEnqueue`). The extension-side `JSValue` element becomes whatever the chosen JavaScript engine binding uses (ClearScript's `ScriptObject`, or Jint's `JsValue`), and the handle-minting scheme (`#<escaped-id>` versus `<parent>/<index>`) ports unchanged, since it is pure string manipulation with no platform dependency. Drive a `Microsoft.UI.Xaml.Controls.TreeView` from `children(of:)`-equivalent calls exactly as the companion `ExtensionTreeViewController` recipe's WinUI note describes, and fire `ProviderReplaced`/invalidate in the same order as **provider-replacement-ordering** from whatever registry class plays the role of `MainThreadTreeViews`.

