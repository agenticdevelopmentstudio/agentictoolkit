<!-- leaf: implement-extension-host-vs-2/code-api-main-thread-window--test-vectors · source: extension-host-vs-code-api-main-thread-window.md -->

# MainThreadWindow

## Conformance Test Vectors

| Input / Call | Expected Output / Effect | Source |
|---|---|---|
| `showInformationMessage()` with no arguments | Promise rejects with `"vscode.window.showInformationMessage requires a message argument."` | `MainThreadWindowTests.swift` |
| `showWarningMessage("text", 42)` | Promise rejects citing argument 1 is neither a string nor an object with a string `title` | `MainThreadWindowTests.swift` |
| `showErrorMessage("text", { title: "Retry" }, { title: "Cancel", isCloseAffordance: true })` | Presenter receives two items; the `Cancel` item is the close affordance | `MainThreadWindowTests.swift` |
| `showQuickPick()` with no arguments | Promise rejects with `"vscode.window.showQuickPick requires an items argument."` | `MainThreadWindowQuickPickTests.swift` |
| `showQuickPick(42)` | Promise rejects with `"...argument 0 is neither an array nor a promise of one."` | `MainThreadWindowQuickPickTests.swift` |
| `showQuickPick(["a", "b"], { canPickMany: true })` and the presenter resolves both | Promise resolves to an array containing both chosen items | `MainThreadWindowQuickPickTests.swift` |
| `showQuickPick` items array longer than `VSCodeAPI.maximumDecodableArrayLength` | Promise rejects citing the array-length limit | `MainThreadWindowQuickPickTests.swift` |
| `showQuickPick(Promise.reject(new Error("boom")))` | Returned promise rejects with the extension's own rejection reason | `MainThreadWindowQuickPickTests.swift` |
| `showInputBox({ valueSelection: [3] })` | Promise rejects with `"...must have exactly two elements, not 1."` | `MainThreadWindowInputBoxTests.swift` |
| `showInputBox({ value: "hi", valueSelection: [1, 5] })` where `value` is length 2 | Promise rejects citing the end offset past the end of `value` | `MainThreadWindowInputBoxTests.swift` |
| `showInputBox({ validateInput: () => "bad" })` on an edit | Presenter reports the input invalid with message `"bad"` and severity `Error` | `MainThreadWindowInputBoxTests.swift` |
| `showInputBox({ validateInput: () => undefined })` on an edit | Presenter reports the input valid | `MainThreadWindowInputBoxTests.swift` |
| `createStatusBarItem("my.id", StatusBarAlignment.Right, 5)` | Presenter creates an item aligned right at priority 5, keyed by an internal identifier derived from `"my.id"` | `MainThreadWindowStatusBarTests.swift` |
| `createStatusBarItem()` twice with the same explicit `id` | Two distinct internal identifiers are created; no collision | `MainThreadWindowStatusBarTests.swift` |
| Setting `.tooltip` to a `MarkdownString`-shaped object | `NotImplementedLedger.record` is called with `memberPath: "vscode.StatusBarItem.tooltip: MarkdownString"`; presenter's tooltip is not updated | `MainThreadWindowStatusBarTests.swift` |
| Setting `.command` to `{ command: "my.cmd", title: "Run" }` | `NotImplementedLedger.record` is called with `memberPath: "vscode.StatusBarItem.command: Command"`; presenter's command is not updated | `MainThreadWindowStatusBarTests.swift` |
| Setting `.command` to the string `"my.cmd"` | Presenter's command is updated to `"my.cmd"`; no ledger record | `MainThreadWindowStatusBarTests.swift` |
| Calling `.hide()` on an item never shown | Presenter's hide call is made unconditionally; no error | `MainThreadWindowStatusBarTests.swift` |
| Calling `.dispose()` then mutating `.text` on the same item | Presenter's dispose call preceded the mutation attempt; the mutation is not forwarded to the presenter for that identifier | `MainThreadWindowStatusBarTests.swift` |
| `createStatusBarItem(undefined, undefined, Infinity)` | Priority forwarded to the presenter as `Infinity`, unclamped | `MainThreadWindowStatusBarTests.swift` (source-documented; not exercised by a dedicated `Infinity` test — see Compliance) |
| `dispose()` on `MainThreadWindow` itself while a `showQuickPick` promise is pending | The pending promise's `PromiseSettlementBox` is marked disposed; the promise never settles | `MainThreadWindowQuickPickTests.swift` |
