<!-- leaf: implement-extension-host-core-2/extensions-webview-panel-options--edge-cases · source: extension-host-core-extensions-webview-panel-options.md -->

# WebviewPanelOptions

**Rules** (cite as `implement-extension-host-core-2/extensions-webview-panel-options--edge-cases#<slug>`):

- `null-input-on-every-option` MUST — WebviewPanelOptions(enableScripts: nil, enableForms: nil, localResourceRoots: nil) is the fully-absent case; it …
- `empty-array-roots-versus-absent-roots` MUST — an empty localResourceRoots array is not the same input as a nil one — the empty array is honored as "no file access at …
- `boundary-extensiondirectory-duplicated-in-workspaceroots` MUST — when the default root list's two sources overlap (an open workspace folder that canonicalizes to the same directory as …
- `concurrent-access` MUST — WebviewPanelOptions holds no mutable stored state — every stored property is a let, and its own methods and static …
- `error-states` MUST — this type defines no throwing function of its own other than the compiler-synthesized init(from:) throws, whose only …

## Edge Cases

- **Null input on every option**: `WebviewPanelOptions(enableScripts: nil, enableForms: nil, localResourceRoots: nil)` is the fully-absent case; it resolves to the safest posture — scripts off, forms off, and the default two-root list (extension directory plus every open workspace folder) once `resourceRoots` is called. MUST.
- **Empty-array roots versus absent roots**: an empty `localResourceRoots` array is not the same input as a `nil` one — the empty array is honored as "no file access at all," while `nil` takes the extension-directory-plus-workspace default. Collapsing the two is the exact hazard the source's own comment names: a panel that deliberately renounced file access must not be handed the whole workspace. MUST.
- **Boundary — extensionDirectory duplicated in workspaceRoots**: when the default root list's two sources overlap (an open workspace folder that canonicalizes to the same directory as `extensionDirectory`), `resourceRoots` keeps only the first occurrence — `extensionDirectory` — and drops the duplicate workspace entry, per `resource-roots-deduplication`. MUST.
- **Concurrent access**: `WebviewPanelOptions` holds no mutable stored state — every stored property is a `let`, and its own methods and static functions read only their arguments and `self`. Calling any of them concurrently, from any thread or actor, against the same or different values requires no synchronization. MUST.
- **Error states**: this type defines no throwing function of its own other than the compiler-synthesized `init(from:) throws`, whose only failure path is `Decoder`'s own `DecodingError` when a present key's JSON value cannot be decoded as its declared type (for example a non-Boolean `enableScripts`); that error propagates untouched — nothing in `WebviewPanelOptions.swift` catches or discards it. Stated as fact, per the absent-feature rule: the source defines no other error condition. MUST.
- **Offline / disconnected state**: not applicable. `WebviewPanelOptions.swift` performs no networking; its only I/O is the local, read-only symlink resolution `resourceRoots` performs through `ExtensionResourcePath.canonicalDirectory`, which has no connectivity state to lose.
- **Cancellation and timeout**: `resourceRoots(extensionDirectory:workspaceRoots:)` and `contentSecurityPolicy` define no timeout and no cancellation, because both are synchronous, non-`async` calls; a slow or unresponsive mount underneath a declared root blocks the caller for as long as symlink resolution takes, with no escape hatch defined in this file. Stated as fact, per the absent-feature rule — not a marker, since nothing in a synchronous options struct's purpose calls for one.
- **A declared root that does not exist on disk**: `resourceRoots` performs no existence check on any declared or default root before canonicalizing it for deduplication; a root naming a directory that has since been deleted or was never created is passed through `ExtensionResourcePath.canonicalDirectory` (whose symlink resolution is a no-op on a path that does not resolve to anything) and returned to the caller unchanged. This is a fact about the collaborator this type delegates canonicalization to, not a gap in this file's own contract.
