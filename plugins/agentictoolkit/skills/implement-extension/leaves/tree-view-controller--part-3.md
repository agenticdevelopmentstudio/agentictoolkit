<!-- leaf: implement-extension/tree-view-controller--part-3 · source: extension-tree-view-controller.md -->

# ExtensionTreeViewController — continued (part 3)

**Rules** (cite as `implement-extension/tree-view-controller--part-3#<slug>`):

- `redraw-preserves-selection` MUST
- `redraw-narrowing-selection-notifies-source` MUST
- `redraw-suppresses-source-notifications` MUST
- `default-expansion-applied-once` MUST
- `expansion-request-triggers-load` MUST
- `expand-collapse-reported-to-source` MUST
- `targeted-change-reloads-one-branch` MUST
- `untargeted-change-reloads-loaded-branches` MUST
- `untargeted-change-reasks-root-when-empty` MUST
- `change-after-teardown-ignored` MUST
- `row-view-recycled` MUST
- `row-icon-from-symbol-name` MUST
- `row-label-shows-item-label` MUST
- `row-caption-from-description` MUST
- `row-tooltip-fallback` MUST
- `row-background-recycled` MUST
- `double-click-activates` MUST
- `return-key-activates-selection` MUST
- `insert-newline-activates-selection` MUST
- `other-keys-pass-through` MUST
- `outline-pane-title-source-or-fallback` MUST
- `outline-teardown-idempotent` MUST
- `outline-teardown-releases-callbacks-only-if-owner` MUST

### Redraw, expansion, selection

- **redraw-preserves-selection**: Redrawing a branch MUST preserve the prior selection across the reload for every previously-selected row that still exists afterward.
- **redraw-narrowing-selection-notifies-source**: If a redraw's restored selection contains fewer rows than were selected before it, the data source MUST be told the selection changed.
- **redraw-suppresses-source-notifications**: While the outline reloads for a redraw, the `NSOutlineView` selection and expand/collapse notifications the reload itself triggers MUST NOT be forwarded to the data source.
- **default-expansion-applied-once**: A child row whose `collapsibleState` is `.expanded` MUST be automatically expanded exactly once, the first time it is drawn under its current parent; a branch the user has since closed MUST stay closed through every later redraw.
- **expansion-request-triggers-load**: Expanding a row whose children have not yet been loaded MUST trigger a load for that row's handle.
- **expand-collapse-reported-to-source**: Expanding or collapsing a row by user action (not by the controller's own automatic expansion or a redraw) MUST report the corresponding `didExpand`/`didCollapse` to the data source.

### Tree-data change notifications

- **targeted-change-reloads-one-branch**: A tree-data change reported for a specific handle whose row is currently in the table MUST reload only that branch.
- **untargeted-change-reloads-loaded-branches**: A tree-data change reported with no handle, or with a handle not currently in the table, MUST re-ask every branch this pane has already loaded.
- **untargeted-change-reasks-root-when-empty**: If the table holds no loaded branches at all when an untargeted change arrives, the root MUST also be asked.
- **change-after-teardown-ignored**: A tree-data change reported after the pane has begun teardown MUST be ignored.

### Row rendering

- **row-view-recycled**: Rows MUST be drawn with a recycled row view, not a freshly built view hierarchy per row.
- **row-icon-from-symbol-name**: A row whose `symbolName` resolves to a system symbol image MUST show that image tinted the `.secondaryText` semantic color; a row with no symbol name, or one that fails to resolve, MUST hide the icon entirely.
- **row-label-shows-item-label**: A row's label MUST show `item.label`, truncating with a tail ellipsis when it does not fit.
- **row-caption-from-description**: A row's caption MUST show `item.description` when it is non-nil and non-empty, and MUST be hidden otherwise.
- **row-tooltip-fallback**: A row's tooltip MUST be `item.tooltip` when present, and MUST fall back to `item.label` otherwise.
- **row-background-recycled**: The row's background view MUST also be a recycled view rather than a freshly built one per row.

### Activation

- **double-click-activates**: Double-clicking a row MUST activate that row's item through the data source.
- **return-key-activates-selection**: Pressing Return (key code 36) or the numeric-keypad Enter (key code 76) while a row is selected MUST activate the selected row's item.
- **insert-newline-activates-selection**: When AppKit interprets Return as the text-editing command instead of delivering it as a raw `keyDown` (i.e. `insertNewline(_:)` is called), the controller MUST activate the selected row's item — the same outcome as `return-key-activates-selection`, reached through the other path AppKit can take.
- **other-keys-pass-through**: A key event that is neither Return nor keypad Enter MUST be passed to `super.keyDown(_:)` rather than consumed.

### Pane title & teardown (outline controller)

- **outline-pane-title-source-or-fallback**: `paneTitle` MUST be `dataSource.title` when it is non-nil and non-empty, and MUST fall back to the contributed view's manifest name otherwise.
- **outline-teardown-idempotent**: `paneContentWillBeDiscarded()` MUST have no additional effect when called more than once on the same instance.
- **outline-teardown-releases-callbacks-only-if-owner**: `paneContentWillBeDiscarded()` MUST clear `onDidChangeTreeData`, `onDidChangeChrome` and `onProviderReplaced` on the data source, and MUST report visibility `false`, only when this pane is still that data source's recorded callback owner at teardown time; a superseded pane's teardown MUST NOT touch a data source it no longer owns.

## Appearance

- **Corner radius**: None anywhere in this file.
- **Padding**: Message banner inset 16pt from the container's leading/trailing edges and 8pt from its top edge (half of the 16pt message inset); the tree sits 8pt below the banner when shown, flush with the container's top edge otherwise. Inside a row, the icon/label/caption stack is inset 2pt from the row's leading edge and at most 6pt from its trailing edge, with 4pt spacing between the three pieces.
- **Font**: Not set as literal point sizes in this file. Message banner: `ThemedLabel(role: .tertiaryText, textRole: .caption)`. Row label: `ThemedLabel(role: .primaryText, textRole: .body)`. Row caption: `ThemedLabel(role: .tertiaryText, textRole: .caption)`. All are theme-resolved semantic fonts (`SemanticPalette.font(_:)`), not literal sizes.
- **Background**: The container view's fill and the outline's own background both track the `.surface` semantic color; the outline's grid color tracks the `.divider` semantic color.
- **Foreground/Text**: Row icon tinted `.secondaryText`; row label `.primaryText`; row caption and message banner `.tertiaryText`. All theme-resolved semantic tokens, never literal color values.
- **Border**: None drawn anywhere in this file.
- **Shadow**: None drawn anywhere in this file.
- **Min/Max size**: The container view's initial frame is 300×200 points in both `loadView()` implementations — only Auto Layout's starting point, not an enforced minimum or maximum. No other size constraint is set by this file; the pane's actual bounds are governed by whatever hosts it, which is out of scope here.

## Accessibility

- **Role/trait**: The outline is a plain `NSOutlineView` (AppKit's own outline/row accessibility roles) carrying the identifier `"<accessibilityPrefix>.tree"`; the message banner is a plain `NSTextField`-based label carrying `"<accessibilityPrefix>.message"`. Neither identifier is an accessibility role or label — `accessibilityID` only sets `accessibilityIdentifier`, a UI-test hook, and this file overrides no AX role anywhere.
- **Label requirements**: A row's label (`item.label`) and caption (`item.description`) are plain `NSTextField` `stringValue`s, which AppKit's default accessibility exposes as the row's accessible text. The icon's `NSImage` is given `accessibilityDescription: nil`, relying on the adjacent label text to name the row rather than describing the icon separately. The message banner's accessible text is its `stringValue`.
- **Announce state changes**: Not implemented in source. Redrawing a branch, toggling the message banner, and the placeholder-to-tree swap post no explicit `NSAccessibility` notification (e.g. `.layoutChanged` or an announcement) anywhere in this file; a VoiceOver user gets no non-visual cue, beyond whatever `reloadItem`/`reloadData` announces on their own, that a branch's children arrived, that the message banner appeared or disappeared, or that the pane swapped from the placeholder to a live tree.
- **Minimum tap target**: Not overridden in this file; row height is a fixed 22pt (`outline-row-height`) with no accessibility-driven exception. macOS's pointer-driven HIG does not carry the 44×44pt minimum that applies to iOS touch targets, and this source sets no explicit minimum of its own.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `view` | `ContributedView` | required at init | The extension's manifest-declared tree view this pane hosts; drives the placeholder, `paneTitle`'s fallback, and the outline's accessibility-id prefix (`registryID`). |
| `extensionDisplayName` | `String` | required at init | Shown by the placeholder while no provider has registered; not consulted again once a tree is shown. |
| `resolve` | `ContributedTreeResolving` (closure) | required at init | Invoked exactly once, from `viewDidLoad()`, to supply the data source. It is never invoked again; a later replacement arrives only through `onProviderReplaced` on that data source (`provider-replacement-swaps-source`). |
| `childrenBudget` | `TimeInterval` | `30` (seconds) | How long a single `getChildren` ask may take before its branch is treated as unanswered; settable, intended for tests. |

