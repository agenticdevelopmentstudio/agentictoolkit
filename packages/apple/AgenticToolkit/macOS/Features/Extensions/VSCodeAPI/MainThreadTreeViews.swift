//
//  MainThreadTreeViews.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore
import os
import AgenticToolkitCore

// MARK: - One registered provider

/// One `TreeDataProvider` an extension registered, as both halves of the seam
/// see it: the pane pulls rows out of it, and the `TreeView` object handed back
/// by `createTreeView` writes chrome into it.
///
/// `ExtensionWebviewPanelModel`'s counterpart, and held the same way —
/// `MainThreadTreeViews.models` is the only strong reference, every block on
/// the JavaScript `TreeView` object captures this **weakly**, and dropping it
/// from that dictionary is what makes all of them go inert at once.
///
/// **The element table is the whole of the bookkeeping.** `TreeDataProvider` is
/// asked for the children of *its own* model objects, so every row the pane
/// draws has to be able to name one back. The elements are `JSValue`s, they
/// belong to the extension's `JSContext`, and they are held here rather than on
/// the items the pane keeps because a `JSValue` stored on something exported to
/// JavaScript is a retain cycle through JavaScriptCore
/// (`JSManagedValue.h:49`) — the same reason `MainThreadWebviews.viewProviders`
/// is a Swift-side dictionary.
@MainActor
final class ExtensionTreeModel: ExtensionTreeDataSource {

    /// The contributed view id this provider was registered for.
    let viewID: String

    /// Distinguishes one registration from the next for the same view id, so a
    /// `Disposable` from the first cannot tear out the second —
    /// `MainThreadWebviews.ViewProviderRegistration.token`'s job exactly.
    let token: UUID

    /// The provider object, held whole rather than its two methods: upstream
    /// reads `getChildren`/`getTreeItem` off the object at call time, so an
    /// extension that swaps a method after registering gets the swap, and
    /// `this` is bound to what its author expects.
    let provider: JSValue

    private let extensionIdentifier: String
    private let commands: CommandRegistry
    private let notImplementedLedger: NotImplementedLedger

    /// Every element the pane currently knows, by the handle it knows it under.
    ///
    /// Handles are minted by `handle(forDeclaredID:parent:index:)` and are
    /// **positional unless the item declared an `id`** — see that method for
    /// why, and for what a reordering tree costs.
    private var elements: [String: JSValue] = [:]

    /// The `TreeItem.command` of each element that declared one, kept whole
    /// because its `arguments` are `any[]` in the extension's own context and
    /// have no Swift form (`ContributedTreeItem.commandID`'s stated split).
    private var commandsByHandle: [String: (id: String, arguments: [JSValue])] = [:]

    /// Which handle each handle was last issued under, and the reverse.
    ///
    /// Recorded rather than read off the handle, because only one of the two
    /// handle spaces carries its parent in its text. `parent/index` does;
    /// `#declaredID` does not, and cannot — a declared id is the extension's
    /// word for a row wherever that row appears. Without this the sweep below
    /// had nothing to go on for a declared handle and silently skipped it, so
    /// the tables grew by every row an extension had ever shown and `activate`
    /// could still find the command of a row that had left the tree.
    private var parentByHandle: [String: String] = [:]
    private var childHandles: [String: [String]] = [:]

    /// The pane's current selection, as handles. The `TreeView` object turns
    /// these back into elements on the way out.
    private var selectedHandles: [String] = []

    private(set) var isVisible = false

    /// The subscription to the provider's own `onDidChangeTreeData`, so it can
    /// be let go when this registration is disposed. A `JSValue`, like the
    /// provider itself, and dropped at the same moment for the same reason.
    private var changeSubscription: JSValue?

    private var isInvalidated = false

    // MARK: ExtensionTreeDataSource

    var title: String? {
        didSet { if title != oldValue { onDidChangeChrome?() } }
    }

    var message: String? {
        didSet { if message != oldValue { onDidChangeChrome?() } }
    }

    var allowsMultipleSelection = false {
        didSet { if allowsMultipleSelection != oldValue { onDidChangeChrome?() } }
    }

    var onDidChangeTreeData: ((String?) -> Void)?
    var onDidChangeChrome: (() -> Void)?

    /// `TreeView.description` (`vscode.d.ts:11288`) — stored so an extension
    /// reads back what it wrote, and shown nowhere. A pane here has a title and
    /// no subtitle, so this is a capability that is not built rather than an
    /// option already satisfied, and the setter records a ledger row.
    var viewDescription: String?

    // MARK: Events the TreeView object publishes

    /// `TreeView.onDidChangeSelection` (`vscode.d.ts:11268`).
    private(set) lazy var selectionChanges = ExtensionEventEmitter<[String]>(
        path: "vscode.TreeView.onDidChangeSelection",
        delay: 0,
        window: ExtensionEventImmediateWindow(),
        merge: { $0.last ?? [] },
        map: { [weak self] handles, context in
            guard let self, let event = JSValue(newObjectIn: context) else { return nil }
            event.setValue(self.elementArray(for: handles, in: context), forProperty: "selection")
            return event
        })

    /// `TreeView.onDidChangeVisibility` (`vscode.d.ts:11273`).
    private(set) lazy var visibilityChanges = ExtensionEventEmitter<Bool>(
        path: "vscode.TreeView.onDidChangeVisibility",
        delay: 0,
        window: ExtensionEventImmediateWindow(),
        merge: { $0.last ?? false },
        map: { visible, context in
            guard let event = JSValue(newObjectIn: context) else { return nil }
            event.setValue(visible, forProperty: "visible")
            return event
        })

    /// `TreeView.onDidExpandElement` (`vscode.d.ts:11258`).
    private(set) lazy var expansions = ExtensionEventEmitter<String>(
        path: "vscode.TreeView.onDidExpandElement",
        delay: 0,
        window: ExtensionEventImmediateWindow(),
        merge: { $0.last ?? "" },
        map: { [weak self] handle, context in
            self?.elementEvent(for: handle, in: context)
        })

    /// `TreeView.onDidCollapseElement` (`vscode.d.ts:11263`).
    private(set) lazy var collapses = ExtensionEventEmitter<String>(
        path: "vscode.TreeView.onDidCollapseElement",
        delay: 0,
        window: ExtensionEventImmediateWindow(),
        merge: { $0.last ?? "" },
        map: { [weak self] handle, context in
            self?.elementEvent(for: handle, in: context)
        })

    /// `TreeView.onDidChangeCheckboxState` (`vscode.d.ts:11278`).
    ///
    /// Real, subscribable, and never fired, for
    /// `ExtensionWebviewPanelModel.viewStateChanges`' reason: an absent member
    /// is a `TypeError` at activation and no tree at all, which is a worse
    /// answer than an event that stays quiet. Nothing here draws a checkbox, so
    /// subscribing records a ledger row.
    private(set) lazy var checkboxChanges = ExtensionEventEmitter<Void>(
        path: "vscode.TreeView.onDidChangeCheckboxState",
        delay: 0,
        window: ExtensionEventImmediateWindow(),
        merge: { _ in () },
        map: { _, context in JSValue(undefinedIn: context) })

    init(
        viewID: String,
        token: UUID,
        provider: JSValue,
        extensionIdentifier: String,
        commands: CommandRegistry,
        notImplementedLedger: NotImplementedLedger
    ) {
        self.viewID = viewID
        self.token = token
        self.provider = provider
        self.extensionIdentifier = extensionIdentifier
        self.commands = commands
        self.notImplementedLedger = notImplementedLedger
    }

    // MARK: - Pulling rows

    func children(of parent: ContributedTreeItem?) async -> [ContributedTreeItem] {
        guard !isInvalidated, let context = provider.context else { return [] }
        guard let getChildren = provider.forProperty("getChildren"),
              MainThreadTreeViews.isFunction(getChildren, in: context) else {
            Self.logger.error(
                """
                \(self.extensionIdentifier, privacy: .public)'s provider for view id \
                \(self.viewID, privacy: .public) has no getChildren to call
                """)
            return []
        }

        let parentHandle = parent?.id ?? ""
        let elementArgument: Any
        if let parent {
            guard let element = elements[parent.id] else {
                // The pane asked about a row this model has forgotten — a
                // branch expanded across a refresh that replaced its parent.
                // An empty branch is the honest answer; the row itself is
                // about to be rebuilt by the refresh that forgot it.
                return []
            }
            elementArgument = element
        } else {
            guard let undefined = JSValue(undefinedIn: context) else { return [] }
            elementArgument = undefined
        }

        let returned: JSValue
        switch VSCodeAPI.call(getChildren, thisArg: provider, arguments: [elementArgument]) {
        case .returned(let value):
            // `undefined`/`null` is a legal `ProviderResult` meaning "no
            // children" (`vscode.d.ts:11361`), and so is a member that
            // returned nothing at all — neither is a failure worth logging.
            guard let value, !value.isUndefined, !value.isNull else { return [] }
            returned = value
        case .threw(let error):
            log("getChildren threw", error)
            return []
        case .unavailable:
            log("getChildren could not be invoked", nil)
            return []
        }

        let settled: JSValue
        switch await VSCodeAPI.settlement(of: returned, in: context) {
        case .fulfilled(let value):
            guard !value.isUndefined, !value.isNull else { return [] }
            settled = value
        case .rejected(let reason):
            log("getChildren rejected", reason)
            return []
        case .unavailable:
            log("getChildren's result could not be settled", nil)
            return []
        }

        guard !isInvalidated else { return [] }
        return await items(from: settled, parentHandle: parentHandle, in: context)
    }

    /// Turns the array a provider answered into rows, minting a handle and a
    /// `TreeItem` for each element.
    private func items(
        from array: JSValue, parentHandle: String, in context: JSContext
    ) async -> [ContributedTreeItem] {
        guard let count = VSCodeAPI.arrayLength(of: array) else {
            log("getChildren answered something that is not an array", nil)
            return []
        }

        // **What is dropped is what this answer did not name, and no more.**
        //
        // The children are taken off the parent before they are rebuilt, so
        // that refiling them below cannot list one twice — but their own
        // subtrees are left alone until the answer is in, and then only the
        // subtrees of children that are actually gone are dropped.
        //
        // Forgetting the whole subtree up front was the bug. A targeted
        // refresh — `onDidChangeTreeData(element)` — reloads exactly this
        // branch, so the pane keeps drawing every grandchild row it had
        // already read. Dropping their elements here left those rows on
        // screen with nothing behind them: clicking one ran no command,
        // opening one answered no children, and nothing ever asked again,
        // because from the pane's side the branch was already read. Only the
        // whole-tree refresh healed it, and only because it re-asks every
        // loaded branch.
        let previousChildren = childHandles.removeValue(forKey: parentHandle) ?? []

        var rows: [ContributedTreeItem] = []
        var reissued: Set<String> = []
        rows.reserveCapacity(count)
        for index in 0..<count {
            guard !isInvalidated, let element = array.atIndex(index) else { continue }
            guard let treeItem = await treeItem(for: element, in: context) else { continue }
            let handle = Self.handle(
                forDeclaredID: Self.string(treeItem.forProperty("id")),
                parent: parentHandle, index: index)
            elements[handle] = element
            file(handle, under: parentHandle)
            reissued.insert(handle)
            rows.append(read(treeItem, element: element, handle: handle, in: context))
        }

        // A branch that shrank: these name rows the extension has stopped
        // listing, so they and everything under them go.
        forget(previousChildren.filter { !reissued.contains($0) })
        return rows
    }

    /// `getTreeItem(element)` settled down to the object it answered.
    private func treeItem(for element: JSValue, in context: JSContext) async -> JSValue? {
        guard let getTreeItem = provider.forProperty("getTreeItem"),
              MainThreadTreeViews.isFunction(getTreeItem, in: context) else {
            log("has no getTreeItem to call", nil)
            return nil
        }
        let returned: JSValue
        switch VSCodeAPI.call(getTreeItem, thisArg: provider, arguments: [element]) {
        case .returned(let value):
            guard let value, !value.isUndefined, !value.isNull else {
                log("getTreeItem answered nothing for an element", nil)
                return nil
            }
            returned = value
        case .threw(let error):
            log("getTreeItem threw", error)
            return nil
        case .unavailable:
            log("getTreeItem could not be invoked", nil)
            return nil
        }
        switch await VSCodeAPI.settlement(of: returned, in: context) {
        case .fulfilled(let value):
            guard value.isObject else {
                log("getTreeItem answered something that is not a TreeItem", nil)
                return nil
            }
            return value
        case .rejected(let reason):
            log("getTreeItem rejected", reason)
            return nil
        case .unavailable:
            log("getTreeItem's result could not be settled", nil)
            return nil
        }
    }

    /// Reads a `TreeItem`'s properties off whatever object the provider
    /// answered.
    ///
    /// **Duck-typed on purpose, never `instanceof vscode.TreeItem`.** Upstream
    /// documents `getTreeItem` as returning `TreeItem | Thenable<TreeItem>` and
    /// accepts any object with the right fields — a plain object literal is
    /// what a large share of published extensions actually return, and a host
    /// that demanded the constructor would reject them while showing an error
    /// that named a type the extension never mentioned.
    private func read(
        _ treeItem: JSValue, element: JSValue, handle: String, in context: JSContext
    ) -> ContributedTreeItem {
        let label = Self.label(of: treeItem, element: element)

        // `description: string | boolean` (`vscode.d.ts:11416`). `true` means
        // "derive it from the resourceUri", which needs a resource model this
        // host does not have, so it reads as absent — stated on
        // `ContributedTreeItem.description`.
        let description = Self.string(treeItem.forProperty("description"))

        // `tooltip: string | MarkdownString` (`:11421`). A `MarkdownString` is
        // read for its `value` and shown as plain text.
        let tooltipValue = treeItem.forProperty("tooltip")
        let tooltip = Self.string(tooltipValue)
            ?? Self.string(tooltipValue?.isObject == true
                ? tooltipValue?.forProperty("value") : nil)

        let stateValue = treeItem.forProperty("collapsibleState")
        let state = ContributedTreeItem.CollapsibleState.read(
            (stateValue?.isNumber ?? false) ? Int(stateValue?.toInt32() ?? 0) : nil)

        let symbolName = symbolName(fromIconPath: treeItem.forProperty("iconPath"))

        // `contextValue` (`:11444`) drives `when` clauses on context menus,
        // which this host contributes none of — an item that sets it is asking
        // for a menu that will not appear, so it is a row rather than silence.
        if Self.string(treeItem.forProperty("contextValue")) != nil {
            notImplementedLedger.record(
                memberPath: "vscode.TreeItem.contextValue",
                extensionIdentifier: extensionIdentifier)
        }
        if let checkbox = treeItem.forProperty("checkboxState"), !checkbox.isUndefined,
           !checkbox.isNull {
            notImplementedLedger.record(
                memberPath: "vscode.TreeItem.checkboxState",
                extensionIdentifier: extensionIdentifier)
        }

        let commandID = readCommand(treeItem.forProperty("command"), handle: handle, in: context)

        return ContributedTreeItem(
            id: handle,
            label: label,
            description: description,
            tooltip: tooltip,
            collapsibleState: state,
            symbolName: symbolName,
            commandID: commandID)
    }

    /// `TreeItem.label: string | TreeItemLabel` (`vscode.d.ts:11396`), falling
    /// back to the `resourceUri`'s last path component and then to the
    /// element's own description — never to a blank row, which is
    /// indistinguishable from a broken pane.
    private static func label(of treeItem: JSValue, element: JSValue) -> String {
        if let plain = string(treeItem.forProperty("label")) { return plain }
        if let structured = treeItem.forProperty("label"), structured.isObject,
           let text = string(structured.forProperty("label")) {
            return text
        }
        if let resource = treeItem.forProperty("resourceUri"), resource.isObject {
            let path = string(resource.forProperty("fsPath")) ?? string(resource.forProperty("path"))
            if let path, !path.isEmpty {
                return (path as NSString).lastPathComponent
            }
        }
        return element.toString() ?? ""
    }

    /// `TreeItem.iconPath: string | Uri | { light, dark } | ThemeIcon`
    /// (`vscode.d.ts:11408`), of which only the `ThemeIcon` case has an answer
    /// here.
    ///
    /// A codicon becomes an SF Symbol through `CodiconSymbols` — the same table
    /// `ContributedViewsBuilder` resolves a view container's icon through, one
    /// tier down, so a contributed view and its rows cannot disagree about what
    /// `$(gear)` looks like (`dry`). Everything else names a file this pane
    /// does not load, and gets a ledger row rather than a blank icon nobody can
    /// account for.
    private func symbolName(fromIconPath iconPath: JSValue?) -> String? {
        guard let iconPath, !iconPath.isUndefined, !iconPath.isNull else { return nil }
        if iconPath.isObject, let id = Self.string(iconPath.forProperty("id")),
           Self.string(iconPath.forProperty("fsPath")) == nil,
           Self.string(iconPath.forProperty("path")) == nil {
            // A `ThemeIcon` with no faithful SF Symbol draws no icon, which is
            // `CodiconSymbols`' own deliberate answer and not a gap of this
            // adaptor's — no row for it.
            return CodiconSymbols.symbolName(forCodicon: id)
        }
        notImplementedLedger.record(
            memberPath: "vscode.TreeItem.iconPath",
            extensionIdentifier: extensionIdentifier)
        return nil
    }

    /// `TreeItem.command` (`vscode.d.ts:11437`) — the id is carried to the
    /// pane so it can offer activation, the arguments stay here.
    private func readCommand(_ command: JSValue?, handle: String, in context: JSContext) -> String? {
        guard let command, command.isObject,
              let id = Self.string(command.forProperty("command")) else { return nil }
        var arguments: [JSValue] = []
        if let list = command.forProperty("arguments"), let count = VSCodeAPI.arrayLength(of: list) {
            for index in 0..<count {
                guard let argument = list.atIndex(index) else { continue }
                arguments.append(argument)
            }
        }
        commandsByHandle[handle] = (id: id, arguments: arguments)
        return id
    }

    // MARK: - Handles

    /// The handle a row is known by, for the lifetime of the branch it is in.
    ///
    /// **Positional unless the item declared an `id`.** `TreeItem.id`
    /// (`vscode.d.ts:11391`) is upstream's stable identity and is used when it
    /// is there. When it is not, upstream falls back to the item's own
    /// rendering and warns; here the fallback is the row's path from the root,
    /// which is stable for a tree whose shape does not change between
    /// refreshes — which is what makes an expanded branch stay expanded. A tree
    /// that *reorders* its rows and declares no ids will keep the expansion on
    /// the position rather than on the row, which is exactly the astonishment
    /// upstream warns about and the reason an extension with a mutable tree
    /// should declare `id`.
    ///
    /// **The two spaces are kept disjoint by escaping, not by the `#`.** A
    /// positional handle is its parent's handle plus `/<index>`, so a row
    /// declaring `id: "src"` gives its first unnamed child the handle
    /// `#src/0` — the very handle a row declaring `id: "src/0"` would get. The
    /// `#` prefix does not separate them, because a declared handle is a
    /// legal *prefix* of a positional one. So `/` is escaped out of declared
    /// ids (and `%` with it, which is what keeps the escaping reversible and
    /// two different ids from escaping to one string). A declared handle
    /// therefore contains no `/` at all, and the two spaces cannot meet.
    private static func handle(forDeclaredID declaredID: String?, parent: String, index: Int) -> String {
        if let declaredID, !declaredID.isEmpty { return "#\(escapedForHandle(declaredID))" }
        return "\(parent)/\(index)"
    }

    /// The declared id as it appears inside a handle. Nothing reads it back —
    /// handles are opaque — so this is about uniqueness, not about being able
    /// to recover the id.
    private static func escapedForHandle(_ declaredID: String) -> String {
        guard declaredID.contains("%") || declaredID.contains("/") else { return declaredID }
        // `%` first: escaping it afterwards would escape the escapes.
        return declaredID
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "/", with: "%2F")
    }

    /// Files `handle` as a child of `parent`, taking it off whatever parent
    /// last claimed it.
    ///
    /// The second half is only ever about declared handles. A positional
    /// handle names one place by construction, so it cannot move; a declared
    /// one is the same id wherever the extension puts it, and an extension that
    /// moves a row between branches would otherwise leave it listed under both
    /// — which is a cycle waiting to be walked.
    private func file(_ handle: String, under parent: String) {
        if let previous = parentByHandle[handle], previous != parent {
            childHandles[previous]?.removeAll { $0 == handle }
        }
        parentByHandle[handle] = parent
        childHandles[parent, default: []].append(handle)
    }

    /// Drops every handle beneath `parent`, at any depth, and the commands that
    /// went with them.
    ///
    /// Walks the recorded parentage rather than matching handle text, which is
    /// what makes it see a declared handle at all. Iterative, and each parent's
    /// child list is *removed* as it is visited rather than read: an extension
    /// that declares the same `id` for a row and one of its own descendants
    /// describes a cycle, and taking the list away on the way past is what
    /// makes the walk finish instead of running until the stack does.
    private func forgetDescendants(of parent: String) {
        forget(childHandles.removeValue(forKey: parent) ?? [])
    }

    /// Drops `handles` themselves and everything recorded beneath them.
    private func forget(_ handles: [String]) {
        var doomed = handles
        while let handle = doomed.popLast() {
            elements.removeValue(forKey: handle)
            commandsByHandle.removeValue(forKey: handle)
            parentByHandle.removeValue(forKey: handle)
            doomed.append(contentsOf: childHandles.removeValue(forKey: handle) ?? [])
        }
    }

    // MARK: - What the pane tells this model

    func activate(_ item: ContributedTreeItem) {
        guard !isInvalidated, let entry = commandsByHandle[item.id] else { return }
        do {
            // Straight to the registry rather than back through
            // `vscode.commands.executeCommand`: the command may belong to
            // another extension or to the app itself, the registry is where
            // all three meet, and the arguments are already `JSValue`s in the
            // right context — which is exactly what `MainThreadCommands`
            // hands it (`handleExecuteCommand`).
            _ = try commands.execute(id: entry.id, arguments: entry.arguments as [Any])
        } catch {
            Self.logger.error(
                """
                \(self.extensionIdentifier, privacy: .public)'s tree row command \
                \(entry.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)
                """)
        }
    }

    func selectionDidChange(to items: [ContributedTreeItem]) {
        let handles = items.map(\.id)
        guard handles != selectedHandles else { return }
        selectedHandles = handles
        selectionChanges.fire(handles)
    }

    func visibilityDidChange(to isVisible: Bool) {
        guard isVisible != self.isVisible else { return }
        self.isVisible = isVisible
        visibilityChanges.fire(isVisible)
    }

    func didExpand(_ item: ContributedTreeItem) {
        expansions.fire(item.id)
    }

    func didCollapse(_ item: ContributedTreeItem) {
        collapses.fire(item.id)
    }

    // MARK: - What the provider tells this model

    /// Subscribes to the provider's `onDidChangeTreeData`, if it has one.
    ///
    /// Optional in `vscode.d.ts:11355`, and genuinely optional in practice: a
    /// tree built once from a static list has nothing to publish. A provider
    /// without one simply never refreshes, which is what it asked for.
    func subscribeToChanges() {
        guard let context = provider.context,
              let event = provider.forProperty("onDidChangeTreeData"),
              MainThreadTreeViews.isFunction(event, in: context) else { return }

        let listener: @convention(block) (JSValue?) -> Void = { [weak self] changed in
            MainActor.assumeIsolated { self?.providerDidChangeTreeData(changed) }
        }
        guard let listenerValue = JSValue(object: listener, in: context) else { return }
        switch VSCodeAPI.call(event, thisArg: provider, arguments: [listenerValue]) {
        case .returned(let disposable):
            changeSubscription = disposable
        case .threw(let error):
            log("onDidChangeTreeData threw while subscribing", error)
        case .unavailable:
            log("onDidChangeTreeData could not be subscribed to", nil)
        }
    }

    /// `T | T[] | undefined | null` (`vscode.d.ts:11355`), resolved back to the
    /// handles the pane knows.
    private func providerDidChangeTreeData(_ changed: JSValue?) {
        guard !isInvalidated else { return }
        guard let changed, !changed.isUndefined, !changed.isNull else {
            onDidChangeTreeData?(nil)
            return
        }
        if let count = VSCodeAPI.arrayLength(of: changed) {
            for index in 0..<count {
                guard let element = changed.atIndex(index) else { continue }
                // One unknown element in the list refreshes the whole tree
                // rather than the rest of the list: the unknown one is the
                // part this model cannot draw the boundary of.
                guard let handle = self.handle(of: element) else {
                    onDidChangeTreeData?(nil)
                    return
                }
                onDidChangeTreeData?(handle)
            }
            return
        }
        onDidChangeTreeData?(handle(of: changed))
    }

    /// The handle an element is filed under, by JavaScript identity.
    ///
    /// A scan rather than an index, because the key is `===` on a `JSValue` and
    /// there is nothing hashable to index it by. It runs once per refresh
    /// event, not once per row, which is what makes the cost the tree's size
    /// and not its size squared.
    private func handle(of element: JSValue) -> String? {
        elements.first { $0.value.isEqual(to: element) }?.key
    }

    // MARK: - The TreeView object's side

    /// The selected elements, as the array `TreeView.selection` answers with.
    func elementArray(for handles: [String], in context: JSContext) -> JSValue? {
        guard let array = JSValue(newArrayIn: context) else { return nil }
        var index = 0
        for handle in handles {
            guard let element = elements[handle] else { continue }
            array.setValue(element, at: index)
            index += 1
        }
        return array
    }

    var selection: [String] { selectedHandles }

    /// `{ element }`, the payload both expansion events carry
    /// (`vscode.d.ts:11212`).
    private func elementEvent(for handle: String, in context: JSContext) -> JSValue? {
        guard let element = elements[handle], let event = JSValue(newObjectIn: context) else {
            return nil
        }
        event.setValue(element, forProperty: "element")
        return event
    }

    // MARK: - Teardown

    /// Stops answering, drops the extension's objects, and releases every
    /// listener — the last of which is what lets the `JSContext` go.
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        if let changeSubscription, let context = changeSubscription.context,
           let dispose = changeSubscription.forProperty("dispose"),
           MainThreadTreeViews.isFunction(dispose, in: context) {
            _ = VSCodeAPI.call(dispose, thisArg: changeSubscription, arguments: [])
        }
        changeSubscription = nil
        elements.removeAll()
        commandsByHandle.removeAll()
        selectedHandles.removeAll()
        selectionChanges.removeListeners(ownedBy: self)
        visibilityChanges.removeListeners(ownedBy: self)
        expansions.removeListeners(ownedBy: self)
        collapses.removeListeners(ownedBy: self)
        checkboxChanges.removeListeners(ownedBy: self)
        onDidChangeTreeData = nil
        onDidChangeChrome = nil
    }

    /// Records a row against this provider, used for every member an extension
    /// can reach that this host reads and drops.
    func recordNotImplemented(_ memberPath: String) {
        notImplementedLedger.record(
            memberPath: memberPath, extensionIdentifier: extensionIdentifier)
    }

    private func log(_ what: String, _ detail: JSValue?) {
        let suffix = detail.flatMap { $0.toString() }.map { ": \($0)" } ?? ""
        Self.logger.error(
            """
            \(self.extensionIdentifier, privacy: .public)'s tree data provider for view id \
            \(self.viewID, privacy: .public) \(what, privacy: .public)\(suffix, privacy: .public)
            """)
    }

    /// A `JSValue` read as a `String`, or `nil` for anything that is not one.
    ///
    /// `isString` rather than `toString()`, which answers `"undefined"` for
    /// `undefined` and `"[object Object]"` for an object — both of which would
    /// reach a user's sidebar as a row's description.
    static func string(_ value: JSValue?) -> String? {
        guard let value, value.isString else { return nil }
        return value.toString()
    }
}

extension ExtensionTreeModel: Loggable {
    static nonisolated let logger = makeLogger()
}

// MARK: - vscode.window.registerTreeDataProvider / createTreeView

/// Installs `vscode.window.registerTreeDataProvider` (`vscode.d.ts:12492`) and
/// `vscode.window.createTreeView` (`:12503`), and the `vscode.TreeView` object
/// the second one hands back (`:11208-11330`).
///
/// **A seventh adaptor rather than more of `MainThreadWebviews`.** Both put
/// something in a contributed view, and there the resemblance stops: a webview
/// provider is called once and never again, while a tree provider is asked for
/// rows for as long as the pane is open, so this adaptor's whole substance is
/// the element bookkeeping `MainThreadWebviews` has no use for. The boundary is
/// the seam, as it was there — this is the only adaptor whose seam points the
/// other way (`ExtensionTreeDataSource`, which the pane calls).
///
/// `@MainActor`, like every adaptor here: `JSValue` is not `Sendable`, and
/// JavaScriptCore calls these blocks on the thread that made the call.
@MainActor
public final class MainThreadTreeViews {

    /// Read back in the torn-down message, and by
    /// `ExtensionHostInstaller.installVSCodeMembers()`.
    public static let registerTreeDataProviderMemberPath = "vscode.window.registerTreeDataProvider"

    /// `vscode.window.createTreeView` (`vscode.d.ts:12503`).
    public static let createTreeViewMemberPath = "vscode.window.createTreeView"

    private let notImplementedLedger: NotImplementedLedger
    private let extensionIdentifier: String

    /// Where a row's `command` is dispatched. The registry rather than this
    /// extension's own `vscode.commands`, because a tree row routinely runs a
    /// command another extension — or the app — contributed.
    private let commands: CommandRegistry

    /// The sole strong reference to every live provider, by contributed view
    /// id. `MainThreadWebviews.viewProviders`' role exactly, and keyed by the
    /// same string for the same reason: the manifest's view id, the argument to
    /// `registerTreeDataProvider`, and `ContributedView.viewID` have to agree
    /// or nothing resolves.
    private var models: [String: ExtensionTreeModel] = [:]

    private var isDisposed = false

    public init(
        notImplementedLedger: NotImplementedLedger,
        extensionIdentifier: String,
        commands: CommandRegistry
    ) {
        self.notImplementedLedger = notImplementedLedger
        self.extensionIdentifier = extensionIdentifier
        self.commands = commands
    }

    /// `.raisedException`: a `Disposable` comes back synchronously
    /// (`vscode.d.ts:12492`), usually straight onto `context.subscriptions`.
    public private(set) lazy var registerTreeDataProvider: Any = VSCodeAPI.member(
        MainThreadTreeViews.registerTreeDataProviderMemberPath,
        of: self,
        whenTornDown: .raisedException
    ) { $0.handleRegisterTreeDataProvider() }

    /// `.raisedException` for its sibling's reason: `createTreeView` returns a
    /// `TreeView` synchronously (`vscode.d.ts:12503`).
    public private(set) lazy var createTreeView: Any = VSCodeAPI.member(
        MainThreadTreeViews.createTreeViewMemberPath,
        of: self,
        whenTornDown: .raisedException
    ) { $0.handleCreateTreeView() }

    // MARK: - Registering

    private func handleRegisterTreeDataProvider() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let path = MainThreadTreeViews.registerTreeDataProviderMemberPath
        guard !isDisposed else {
            return VSCodeAPI.raise(
                "\(path) is unavailable: this extension's host has been torn down.", in: context)
        }

        let arguments = VSCodeAPI.currentArguments()
        guard let viewIDArgument = arguments.first, viewIDArgument.isString,
              let viewID = viewIDArgument.toString() else {
            return VSCodeAPI.raise(
                "\(path)'s first argument must be a view id string.", in: context)
        }
        let providerArgument: JSValue? = arguments.count > 1 ? arguments[1] : nil
        guard let provider = validProvider(providerArgument, path: path, in: context) else {
            return nil
        }

        let model = adopt(provider, for: viewID)
        return VSCodeAPI.disposable(in: context) { [weak self] in
            self?.forget(viewID, token: model.token)
        }
    }

    private func handleCreateTreeView() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let path = MainThreadTreeViews.createTreeViewMemberPath
        guard !isDisposed else {
            return VSCodeAPI.raise(
                "\(path) is unavailable: this extension's host has been torn down.", in: context)
        }

        let arguments = VSCodeAPI.currentArguments()
        guard let viewIDArgument = arguments.first, viewIDArgument.isString,
              let viewID = viewIDArgument.toString() else {
            return VSCodeAPI.raise(
                "\(path)'s first argument must be a view id string.", in: context)
        }
        guard arguments.count > 1, arguments[1].isObject else {
            return VSCodeAPI.raise(
                "\(path)'s second argument must be a TreeViewOptions object.", in: context)
        }
        let options = arguments[1]
        guard let provider = validProvider(
            options.forProperty("treeDataProvider"), path: path, in: context) else {
            return nil
        }

        let model = adopt(provider, for: viewID)
        readOptions(options, into: model)
        return MainThreadTreeViews.makeTreeViewObject(for: model, of: self, in: context)
    }

    /// The provider argument both members take, checked for the two methods
    /// they will be called through.
    ///
    /// The *methods* are checked for, not just the object, for
    /// `MainThreadWebviews.handleRegisterWebviewViewProvider`'s stated reason:
    /// an object without them is a mistake that is silent until the first row
    /// is asked for, which is after the pane is on screen and empty.
    private func validProvider(
        _ value: JSValue?, path: String, in context: JSContext
    ) -> JSValue? {
        guard let value, value.isObject,
              MainThreadTreeViews.isFunction(value.forProperty("getChildren"), in: context),
              MainThreadTreeViews.isFunction(value.forProperty("getTreeItem"), in: context) else {
            VSCodeAPI.raise(
                """
                \(path) requires a TreeDataProvider with getChildren(element) and \
                getTreeItem(element) methods.
                """,
                in: context)
            return nil
        }
        return value
    }

    /// Takes over as the live provider for `viewID`, retiring whatever was
    /// there.
    ///
    /// Last registration wins and is logged, as a webview view provider's
    /// does — and for the identical reason: the registration VS Code would
    /// refuse is the one an extension makes after a reload, and taking the
    /// app's word over the extension's would leave a live pane wired to a dead
    /// context.
    private func adopt(_ provider: JSValue, for viewID: String) -> ExtensionTreeModel {
        if let existing = models[viewID] {
            Self.logger.error(
                """
                \(self.extensionIdentifier, privacy: .public) registered a second tree data \
                provider for view id \(viewID, privacy: .public); the later one wins
                """)
            existing.invalidate()
        }
        let model = ExtensionTreeModel(
            viewID: viewID,
            token: UUID(),
            provider: provider,
            extensionIdentifier: extensionIdentifier,
            commands: commands,
            notImplementedLedger: notImplementedLedger)
        models[viewID] = model
        model.subscribeToChanges()
        return model
    }

    private func forget(_ viewID: String, token: UUID) {
        guard let model = models[viewID], model.token == token else { return }
        model.invalidate()
        models.removeValue(forKey: viewID)
    }

    /// `TreeViewOptions` (`vscode.d.ts:11228-11253`) — one option honoured,
    /// three recorded.
    private func readOptions(_ options: JSValue, into model: ExtensionTreeModel) {
        if let many = options.forProperty("canSelectMany"), many.isBoolean {
            model.allowsMultipleSelection = many.toBool()
        }
        // `showCollapseAll` asks for a title-bar button this pane does not
        // have; a drag controller and manual checkbox state ask for surfaces it
        // does not draw at all. Each is a capability that is not built rather
        // than an option already satisfied, so each is a row.
        if let collapseAll = options.forProperty("showCollapseAll"), collapseAll.isBoolean,
           collapseAll.toBool() {
            model.recordNotImplemented("vscode.TreeViewOptions.showCollapseAll")
        }
        if let controller = options.forProperty("dragAndDropController"), controller.isObject {
            model.recordNotImplemented("vscode.TreeViewOptions.dragAndDropController")
        }
        if let manual = options.forProperty("manageCheckboxStateManually"), manual.isBoolean,
           manual.toBool() {
            model.recordNotImplemented("vscode.TreeViewOptions.manageCheckboxStateManually")
        }
    }

    // MARK: - What the pane asks

    /// Whether this extension has a provider registered for `viewID`.
    ///
    /// `MainThreadWebviews.hasViewProvider(for:)`'s twin, asked in the same
    /// place and for the same reason: a provider is registered from
    /// `activate`, so before that the honest answer for an awake-on-demand
    /// extension is "no."
    public func hasTreeDataProvider(for viewID: String) -> Bool {
        !isDisposed && models[viewID] != nil
    }

    /// The data source a pane for `viewID` should pull its rows from, or `nil`
    /// when this extension has registered none.
    public func treeDataSource(for viewID: String) -> (any ExtensionTreeDataSource)? {
        guard !isDisposed else { return nil }
        return models[viewID]
    }

    // MARK: - The TreeView object

    /// Builds the JS-visible `TreeView` (`vscode.d.ts:11208-11330`).
    ///
    /// Every block below captures `model` and `treeViews` **weakly** and stores
    /// no `JSValue` on either — `MainThreadWebviews.makePanelObject`'s
    /// no-capture contract, which holds here for the same reason it holds
    /// there.
    private static func makeTreeViewObject(
        for model: ExtensionTreeModel, of treeViews: MainThreadTreeViews, in context: JSContext
    ) -> JSValue? {
        guard let object = JSValue(newObjectIn: context) else { return nil }

        MainThreadWindow.installAccessor(on: object, name: "title",
            get: { [weak model] in model?.title ?? nil },
            set: { [weak model] value in model?.title = string(value) })

        MainThreadWindow.installAccessor(on: object, name: "message",
            get: { [weak model] in model?.message ?? nil },
            set: { [weak model] value in model?.message = string(value) })

        // Stored, readable, and drawn nowhere — see
        // `ExtensionTreeModel.viewDescription`. The row is recorded on the
        // write, not the read: an extension that never sets it is not waiting
        // on anything.
        MainThreadWindow.installAccessor(on: object, name: "description",
            get: { [weak model] in model?.viewDescription ?? nil },
            set: { [weak model] value in
                guard let model else { return }
                model.viewDescription = string(value)
                model.recordNotImplemented("vscode.TreeView.description")
            })

        // `badge` (`vscode.d.ts:11299`) is a count on the view's container
        // icon, and nothing here draws one.
        MainThreadWindow.installAccessor(on: object, name: "badge",
            get: { JSContext.current().map { JSValueBridge.undefinedOrNull(in: $0) } },
            set: { [weak model] value in
                guard let model, let value, !value.isUndefined, !value.isNull else { return }
                model.recordNotImplemented("vscode.TreeView.badge")
            })

        MainThreadWindow.installReadonlyGetter(on: object, name: "visible") { [weak model] in
            model?.isVisible ?? false
        }

        MainThreadWindow.installReadonlyGetter(on: object, name: "selection") { [weak model] in
            guard let model, let context = JSContext.current() else { return nil }
            return model.elementArray(for: model.selection, in: context)
        }

        install(event: "onDidChangeSelection", on: object, for: model) { $0.selectionChanges }
        install(event: "onDidChangeVisibility", on: object, for: model) { $0.visibilityChanges }
        install(event: "onDidExpandElement", on: object, for: model) { $0.expansions }
        install(event: "onDidCollapseElement", on: object, for: model) { $0.collapses }

        let onDidChangeCheckboxState: @convention(block) () -> JSValue? = { [weak model] in
            MainActor.assumeIsolated {
                guard let model, let context = JSContext.current() else {
                    return UncheckedJSValueBox(value: nil)
                }
                model.recordNotImplemented("vscode.TreeView.onDidChangeCheckboxState")
                return UncheckedJSValueBox(value: model.checkboxChanges.subscribe(
                    arguments: VSCodeAPI.currentArguments(), in: context, owner: model))
            }.value
        }
        object.setObject(
            onDidChangeCheckboxState, forKeyedSubscript: "onDidChangeCheckboxState" as NSString)

        // `reveal(element, options)` (`vscode.d.ts:11325`) scrolls a row into
        // view, selects it and expands its ancestors — none of which this pane
        // can be asked to do from here, because the rows it holds are the ones
        // it has already pulled and an arbitrary element may be in a branch
        // nobody has opened. A resolved promise rather than a rejected one:
        // upstream's `reveal` resolves with `void`, and an extension that
        // `await`s it should carry on rather than take a failure branch for a
        // cosmetic operation.
        let reveal: @convention(block) () -> JSValue? = { [weak model] in
            MainActor.assumeIsolated {
                guard let context = JSContext.current() else {
                    return UncheckedJSValueBox(value: nil)
                }
                model?.recordNotImplemented("vscode.TreeView.reveal")
                return UncheckedJSValueBox(
                    value: VSCodeAPI.resolvedPromise(with: nil, in: context))
            }.value
        }
        object.setObject(reveal, forKeyedSubscript: "reveal" as NSString)

        let dispose: @convention(block) () -> Void = { [weak model, weak treeViews] in
            MainActor.assumeIsolated {
                guard let model else { return }
                treeViews?.forget(model.viewID, token: model.token)
            }
        }
        object.setObject(dispose, forKeyedSubscript: "dispose" as NSString)

        return object
    }

    /// Installs one `Event` member that subscribes to one of the model's
    /// emitters.
    ///
    /// The emitter is reached through a closure rather than passed in, so that
    /// the `lazy var` holding it is built on first subscription rather than on
    /// every `createTreeView` — four emitters for four events an extension is
    /// unlikely to want all of.
    private static func install<Payload>(
        event name: String,
        on object: JSValue,
        for model: ExtensionTreeModel,
        emitter: @escaping @MainActor (ExtensionTreeModel) -> ExtensionEventEmitter<Payload>
    ) {
        let subscribe: @convention(block) () -> JSValue? = { [weak model] in
            MainActor.assumeIsolated {
                guard let model, let context = JSContext.current() else {
                    return UncheckedJSValueBox(value: nil)
                }
                return UncheckedJSValueBox(value: emitter(model).subscribe(
                    arguments: VSCodeAPI.currentArguments(), in: context, owner: model))
            }.value
        }
        object.setObject(subscribe, forKeyedSubscript: name as NSString)
    }

    // MARK: - Small helpers

    /// `x instanceof Function` — `MainThreadWebviews`' own check, which
    /// `isObject` cannot stand in for because `isObject` is true of `{}`.
    ///
    /// A second copy rather than a shared one: `MainThreadWebviews`' is
    /// `private`, and promoting it would make a one-line predicate part of that
    /// class's surface for the sake of saving four lines here.
    static func isFunction(_ value: JSValue?, in context: JSContext) -> Bool {
        guard let value, let functionConstructor = context.objectForKeyedSubscript("Function") else {
            return false
        }
        return value.isInstance(of: functionConstructor)
    }

    private static func string(_ value: JSValue?) -> String? {
        ExtensionTreeModel.string(value)
    }

    // MARK: - Teardown

    /// Drops every registration and every listener.
    ///
    /// Called from `InstalledExtension.dispose()` beside `webviews.dispose()`.
    /// Nothing here owns a view controller — a tree pane outlives its provider
    /// and falls back to saying the extension is gone — so this forgets rather
    /// than closes, which is the one way it differs from `MainThreadWebviews`.
    public func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        for model in models.values {
            model.invalidate()
        }
        models.removeAll()
    }
}

extension MainThreadTreeViews: Loggable {
    public static nonisolated let logger = makeLogger()
}
