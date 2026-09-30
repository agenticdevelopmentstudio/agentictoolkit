<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-tree-views--part-3 · source: extension-host-vs-code-api-main-thread-tree-views.md -->

# MainThreadTreeViews — continued (part 3)

**Rules** (cite as `implement-extension-host-vs-1/code-api-main-thread-tree-views--part-3#<slug>`):

- `description-true-reads-as-absent` MUST
- `tooltip-markdown-string-reads-as-plain-text` MUST
- `collapsible-state-clamps-unknown-to-none` MUST
- `icon-path-theme-icon-resolves-via-codicon-symbols` MUST
- `icon-path-other-cases-record-not-implemented` MUST
- `context-value-records-not-implemented-on-any-value` MUST
- `checkbox-state-records-not-implemented-on-any-defined-value` MUST
- `command-is-read-and-cleared-on-absence` MUST
- `command-arguments-are-forwarded-as-jsvalues-unconverted` MUST
- `activate-runs-through-the-command-registry-directly` MUST
- `activate-is-a-no-op-with-no-stored-command` MUST
- `activate-catches-and-logs-a-thrown-registry-error` MUST
- `change-with-nil-refreshes-the-whole-tree` MUST
- `change-with-an-array-fires-once-per-resolved-element` MUST
- `change-with-an-unknown-or-ambiguous-element-refreshes-the-whole-tree` MUST
- `element-match-is-by-javascript-identity-with-ambiguity-detection` MUST
- `selection-reporting-suppresses-unchanged-selections` MUST
- `visibility-reporting-suppresses-unchanged-visibility` MUST
- `expand-collapse-always-fire` MUST
- `checkbox-change-event-is-real-but-never-fired` MUST
- `title-message-accessors-forward-to-the-model` MUST
- `description-accessor-records-not-implemented-only-on-write` MUST
- `badge-accessor-ignores-reads-and-records-non-nullish-writes` MUST
- `visible-and-selection-are-readonly` MUST
- `event-emitters-are-built-lazily-on-first-subscription` MUST
- `reveal-always-records-not-implemented-and-resolves` MUST
- `treeview-object-blocks-capture-model-and-treeviews-weakly` MUST
- `treeview-dispose-forgets-through-the-owning-registration` MUST
- `disposal-invalidates-every-live-model` MUST
- `invalidate-is-idempotent-and-releases-the-change-subscription` MUST

- **description-true-reads-as-absent**: `ContributedTreeItem.description` MUST be `nil` both when `TreeItem.description` is absent and when it is the JavaScript boolean `true`, since deriving a description from `resourceUri` (upstream's meaning of `true`) has no resource model on this host to derive it from; only a `TreeItem.description` that is itself a string MUST be carried through.
- **tooltip-markdown-string-reads-as-plain-text**: `read(_:element:handle:in:)` MUST read `TreeItem.tooltip` as a plain string when it is one, and otherwise, when it is an object, MUST read its `value` property as a plain string; a `MarkdownString` tooltip's markup is never rendered, only its `value` text.
- **collapsible-state-clamps-unknown-to-none**: `ContributedTreeItem.CollapsibleState.read(_:)` MUST map `1` to `.collapsed` and `2` to `.expanded`, and MUST map every other value (including `nil` and any integer outside `0...2`) to `.none`.
- **icon-path-theme-icon-resolves-via-codicon-symbols**: `symbolName(fromIconPath:)` MUST resolve a `ThemeIcon`-shaped value (an object with a string `id` and no `fsPath` or `path` string) to `CodiconSymbols.symbolName(forCodicon: id)`, and MUST return that call's result unchanged, including `nil` for a codicon `CodiconSymbols` has no SF Symbol for.
- **icon-path-other-cases-record-not-implemented**: `symbolName(fromIconPath:)` MUST call `notImplementedLedger.record(memberPath: "vscode.TreeItem.iconPath", extensionIdentifier:)` and return `nil` for every non-`nil`, non-`undefined` `iconPath` value that is not the `ThemeIcon` shape in **icon-path-theme-icon-resolves-via-codicon-symbols** (a string, a `Uri`/`fsPath`-bearing object, or a `{ light, dark }` object).
- **context-value-records-not-implemented-on-any-value**: `read(_:element:handle:in:)` MUST call `notImplementedLedger.record(memberPath: "vscode.TreeItem.contextValue", extensionIdentifier:)` whenever `TreeItem.contextValue` is a non-`nil` string, since this host contributes no `when`-clause context menus for a tree row to drive.
- **checkbox-state-records-not-implemented-on-any-defined-value**: `read(_:element:handle:in:)` MUST call `notImplementedLedger.record(memberPath: "vscode.TreeItem.checkboxState", extensionIdentifier:)` whenever `TreeItem.checkboxState` is present and is neither `undefined` nor `null`, including the falsy value `0`.
- **command-is-read-and-cleared-on-absence**: `readCommand(_:handle:in:)` MUST store `(id, arguments)` in `commandsByHandle[handle]` and return `id` when `TreeItem.command` is an object with a string `command` property; when it is not (absent, not an object, or missing that property), it MUST call `commandsByHandle.removeValue(forKey: handle)` and return `nil`, so a row whose extension has withdrawn its command cannot go on running the command it declared on a previous refresh under the same handle.
- **command-arguments-are-forwarded-as-jsvalues-unconverted**: `readCommand(_:handle:in:)` MUST read `command.arguments` as a `JSValue` array via `VSCodeAPI.arrayLength(of:)` and `atIndex(_:)`, and MUST store each element as the `JSValue` it already is, with no conversion through `toObject()` or any other bridging.
- **activate-runs-through-the-command-registry-directly**: `activate(_:)` MUST dispatch a row's stored command through `commands.execute(id:arguments:)` (the same `CommandRegistry` `MainThreadCommands.handleExecuteCommand` uses), and MUST NOT go back through `vscode.commands.executeCommand`, because the command may belong to another extension or to the app itself and the registry is where all three meet.
- **activate-is-a-no-op-with-no-stored-command**: `activate(_:)` MUST have no effect, and MUST NOT call `commands.execute`, when `commandsByHandle[item.id]` has no entry (including when the model `isInvalidated`).
- **activate-catches-and-logs-a-thrown-registry-error**: `activate(_:)` MUST catch any error `commands.execute(id:arguments:)` throws, MUST log it at `error` level with the extension identifier and the command id, and MUST NOT propagate it to the caller.
- **change-with-nil-refreshes-the-whole-tree**: `providerDidChangeTreeData(_:)` MUST call `onDidChangeTreeData?(nil)` when its argument is `nil`, JavaScript `undefined`, or JavaScript `null`.
- **change-with-an-array-fires-once-per-resolved-element**: `providerDidChangeTreeData(_:)` MUST, when its argument is a JavaScript array, call `onDidChangeTreeData?(handle)` once for each element that resolves to exactly one known handle via `match(_:)`, in the array's own order.
- **change-with-an-unknown-or-ambiguous-element-refreshes-the-whole-tree**: `providerDidChangeTreeData(_:)` MUST call `onDidChangeTreeData?(nil)` and return, without processing any further elements in the array, as soon as `match(_:)` answers `.none` or `.ambiguous` for any array element or for a single non-array argument.
- **element-match-is-by-javascript-identity-with-ambiguity-detection**: `match(_:)` MUST scan every entry in `elements` and compare with `isEqual(to:)` (JavaScript `===`), MUST answer `.one(handle)` when exactly one entry matches, `.none` when zero match, and MUST answer `.ambiguous` — even though it has already found one match — as soon as a second matching entry is found, since `===` is value equality for a primitive element and the same primitive can legitimately be filed under two handles.
- **selection-reporting-suppresses-unchanged-selections**: `selectionDidChange(to:)` MUST compare the new selection's handles against `selectedHandles` and MUST return without firing `selectionChanges` when they are equal.
- **visibility-reporting-suppresses-unchanged-visibility**: `visibilityDidChange(to:)` MUST compare the new value against `isVisible` and MUST return without firing `visibilityChanges` when they are equal.
- **expand-collapse-always-fire**: `didExpand(_:)` and `didCollapse(_:)` MUST call `expansions.fire(item.id)` and `collapses.fire(item.id)` respectively on every call, with no suppression of a repeated expand or collapse of the same row.
- **checkbox-change-event-is-real-but-never-fired**: `checkboxChanges` MUST be a subscribable `ExtensionEventEmitter<Void>`, and no code path in this file MUST ever call `checkboxChanges.fire`; subscribing to it MUST call `model.recordNotImplemented("vscode.TreeView.onDidChangeCheckboxState")`.
- **title-message-accessors-forward-to-the-model**: the `TreeView` object's `title` and `message` accessors MUST read and write `model.title` and `model.message` unchanged, through weak references to `model`.
- **description-accessor-records-not-implemented-only-on-write**: the `TreeView` object's `description` accessor's getter MUST return `model.viewDescription` unchanged; its setter MUST store the written value into `model.viewDescription` and MUST call `model.recordNotImplemented("vscode.TreeView.description")` on every write, whether or not the pane draws a subtitle anywhere.
- **badge-accessor-ignores-reads-and-records-non-nullish-writes**: the `TreeView` object's `badge` accessor's getter MUST always answer `undefined`/`null` (via `JSValueBridge.undefinedOrNull(in:)`) regardless of any value ever written; its setter MUST call `model.recordNotImplemented("vscode.TreeView.badge")` only when the written value is non-`nil`, not `undefined`, and not `null`.
- **visible-and-selection-are-readonly**: the `TreeView` object MUST expose `visible` and `selection` only as readonly getters (`MainThreadWindow.installReadonlyGetter`), backed by `model.isVisible` and `model.elementArray(for: model.selection, in:)` respectively.
- **event-emitters-are-built-lazily-on-first-subscription**: `selectionChanges`, `visibilityChanges`, `expansions`, `collapses`, and `checkboxChanges` MUST each be a `lazy var`, so an `ExtensionEventEmitter` for an event this extension never subscribes to is never constructed.
- **reveal-always-records-not-implemented-and-resolves**: the `TreeView` object's `reveal` member MUST call `model.recordNotImplemented("vscode.TreeView.reveal")` on every call and MUST return `VSCodeAPI.resolvedPromise(with: nil, in: context)`, regardless of the element or options passed to it; it MUST NOT reject and MUST NOT scroll, select, or expand any row.
- **treeview-object-blocks-capture-model-and-treeviews-weakly**: every block installed on the `TreeView` object (`title`/`message`/`description`/`badge` accessors, the four `install(event:...)` subscriptions, `onDidChangeCheckboxState`, `reveal`, `dispose`) MUST capture `model` and, where applicable, `treeViews`, only as `[weak ...]`, and MUST NOT retain a `JSValue` of its own.
- **treeview-dispose-forgets-through-the-owning-registration**: the `TreeView` object's `dispose` member MUST call `treeViews?.forget(model.viewID, token: model.token)`, subject to the same token guard as **registration-disposable-is-token-guarded**.
- **disposal-invalidates-every-live-model**: `MainThreadTreeViews.dispose()` MUST call `invalidate()` on every model in `models` and MUST leave `models` empty when it returns; it MUST be idempotent, doing nothing on a second call.
- **invalidate-is-idempotent-and-releases-the-change-subscription**: `ExtensionTreeModel.invalidate()` MUST do nothing on any call after its first; on its first call it MUST dispose `changeSubscription` (if present, via its own `dispose` member), set it to `nil`, clear `elements`, `commandsByHandle`, `parentByHandle`, `childHandles`, and `selectedHandles`, remove every listener this model owns from all five event emitters, and set `onDidChangeTreeData` and `onDidChangeChrome` to `nil`; it MUST set `onProviderReplaced` to `nil` only after any pending `onProviderReplaced?(model)` call this invalidation is part of has already fired, per **provider-replacement-ordering**.
