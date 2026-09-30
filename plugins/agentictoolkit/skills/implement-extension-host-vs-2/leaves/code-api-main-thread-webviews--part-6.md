<!-- leaf: implement-extension-host-vs-2/code-api-main-thread-webviews--part-6 · source: extension-host-vs-code-api-main-thread-webviews.md -->

# MainThreadWebviews — continued (part 6)

## Design Decisions

**Decision**: `panels[panel.panelID]` is the sole strong reference to an `ExtensionWebviewPanelModel`, and `forget` (dropping that dictionary entry) is what makes a disposed panel's JavaScript surface go inert, rather than a per-block `isDisposed` flag check inside every closure.
**Rationale**: a webview holds a whole web content process, so its lifetime has to be answerable in one place, not re-derived by every closure that captures the model. Making the dictionary entry the single point of truth means `dispose()`'s job is exactly "drop every entry," and every closure that captures `model` weakly (or captures `panelID` by value, per **wire-captures-the-panel-id-by-value**) simply stops finding anything to call once its entry is gone — there is no second flag that could drift out of sync with the dictionary's own state.
**Approved**: pending

**Decision**: a hand-over (`restore` or `resolveWebviewView`) whose panel is already `isDisposed` at the moment of the call is refused outright — never adopted, never wired, never handed the object — rather than adopted and immediately torn down.
**Rationale**: `onDidDispose` has already fired for a panel that closed while its extension was still waking up, so adopting it would wire a disposal callback that can never fire again: the model, the panel, its page, and the JavaScript object the extension is holding would stay alive — retained by `panels` — until the whole extension is unloaded, while the extension goes on believing it has a live panel to post messages to. Refusing leaves exactly what closing a pane should leave: nothing.
**Approved**: pending

**Decision**: an extension whose `deserializeWebviewPanel` or `resolveWebviewView` throws keeps its adopted panel; only a dispatch that could not be invoked at all (`.unavailable`) triggers `abandon`.
**Rationale**: a throw is the extension's own bug in code that already received a live, wired panel — closing that panel out from under it would compound the bug into a second failure (a pane vanishing) the extension never asked for and cannot recover from. A dispatch that could never be invoked at all never gave the extension anything to hold, so there is nothing to protect by leaving it adopted, and abandoning frees the blank pane instead of leaking it.
**Approved**: pending

**Decision**: `webview.options`'s getter answers only the roots the extension explicitly declared (omitting the field when nothing was declared), while `webview.localResourceRoots`'s getter answers the live, resolved roots.
**Rationale**: `options` is the read-modify-write surface (`vscode.d.ts`) — an extension reads it, flips a field, and writes it back, and if the getter answered the *resolved* defaults, that write-back would freeze the extension directory and the workspace folders open at read time into an explicit declaration, so a workspace folder opened afterward would stop reaching the page. `localResourceRoots` has no such round trip to protect and exists specifically to answer what the panel can read from right now.
**Approved**: pending

**Decision**: `webview.localResourceRoots`'s setter refuses the whole assignment when the value cannot be parsed as a list of `Uri`s at all, while `resourceRootsField`'s array-element parsing drops only the unparseable entries of a value that *is* a list.
**Rationale**: the two failure shapes carry opposite security consequences. A value that is not a list at all (an extension bug, or a nullish assignment) refusing outright keeps the panel's current, working roots in place; substituting an empty list instead would silently revoke file access the extension never asked to give up. A list that is mostly valid dropping only its bad entries keeps as much of the extension's explicit declaration intact as can be honored, which is the opposite risk (granting less than declared, never more).
**Approved**: pending
