<!-- leaf: implement-extension-host-vs-presenting/code-api-extension-status-bar-presenting · source: extension-host-vs-code-api-extension-status-bar-presenting.md -->

**Rules** (cite as `implement-extension-host-vs-presenting/code-api-extension-status-bar-presenting#<slug>`):

- `main-actor-isolation` MUST
- `class-bound-conformance` MUST
- `two-operation-contract` MUST
- `synchronous-no-await` MUST
- `put-or-refresh-semantics` MUST
- `caller-commits-once-per-change` MUST
- `no-debounce-assumed` MUST
- `never-called-for-hidden-or-disposed` MUST
- `remove-tolerates-unknown-id` MUST
- `remove-key-is-internal-id` MUST
- `internal-id-not-exposed` MUST
- `fixed-identity-fields` MUST
- `mutable-display-fields` MUST
- `priority-nil-means-undefined` MUST
- `alignment-two-cases` MUST
- `color-flat-string` MUST
- `value-equatable` MUST
- `sendable-value-types` MUST
- `cross-actor-before-applying` MAY
- `designated-initializer` MUST
- `void-return-no-failure-channel` MUST
- `serialized-calls` MUST

# ExtensionStatusBarPresenting

## Overview

`ExtensionStatusBarPresenting` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionStatusBarPresenting.swift`) is the presenter seam behind `vscode.window.createStatusBarItem`: the interface `MainThreadWindow` calls into whenever a returned `StatusBarItem` object's `show()`, `hide()`, or `dispose()` method runs, or one of its mutable property setters commits a change. Its own header comment says it was split out of `MainThreadWindow.swift`, which had grown past 2,800 lines, and that the split is a file boundary rather than a tier boundary — `MainThreadWindow` is still its only consumer. The same file also declares the two value types the protocol's two methods pass across that seam: `ExtensionStatusBarAlignment` (VS Code's `StatusBarAlignment` enum, reduced to `left`/`right`) and `ExtensionStatusBarItemRequest` (one `createStatusBarItem()` call's current display state, reduced to what a presenter needs to render it). The type carries no rendering logic, no AppKit import, and no state of its own; the production conformer is `WindowFooterStatusBarPresenter` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/WindowFooterStatusBarPresenter.swift`), which renders every shown item into the trailing slot of each open window's `WindowFooterBar`, and the test suite exercises the contract through a recording double, `RecordingStatusBarPresenter` (`MainThreadWindowStatusBarTests.swift`).

## Behavioral Requirements

- **main-actor-isolation**: `ExtensionStatusBarPresenting` MUST be declared `@MainActor`, matching every protocol in its directory; a conforming type's implementations of `putOrUpdateStatusBarItem(_:)` and `removeStatusBarItem(internalID:)` MUST execute on the main actor.
- **class-bound-conformance**: `ExtensionStatusBarPresenting` MUST constrain conformers to `AnyObject`; a value type MUST NOT be able to conform to the protocol as declared.
- **two-operation-contract**: A conforming type MUST implement exactly two members, `putOrUpdateStatusBarItem(_:)` and `removeStatusBarItem(internalID:)`; the protocol MUST NOT declare separate members mirroring VS Code's upstream `show()`, `hide()`, a debounced `update()`, and `dispose()`, because `hide()` and `dispose()` resolve to the same removal effect upstream and nothing here replicates `update()`'s debounce.
- **synchronous-no-await**: Both `putOrUpdateStatusBarItem(_:)` and `removeStatusBarItem(internalID:)` MUST be non-`async` functions that return `Void` synchronously; neither MUST suspend to await a result, unlike `ExtensionQuickPickPresenting.presentQuickPick(_:onHighlight:)`, which awaits the user's choice.
- **put-or-refresh-semantics**: `putOrUpdateStatusBarItem(_:)` MUST put `request` up as a new item when `request.internalID` is not currently shown by the conformer, and MUST refresh the already-shown item in place when `request.internalID` is already up; one method MUST serve both the initial "add" and every subsequent "update".
- **caller-commits-once-per-change**: The caller MUST invoke `putOrUpdateStatusBarItem(_:)` exactly once for every committed change to a shown item's state; the caller MUST NOT batch two or more property changes into a single call.
- **no-debounce-assumed**: A conforming presenter MUST NOT assume any minimum interval, coalescing, or debounce between successive `putOrUpdateStatusBarItem(_:)` calls for the same `internalID`; none is performed on its behalf.
- **never-called-for-hidden-or-disposed**: The caller MUST NOT invoke `putOrUpdateStatusBarItem(_:)` for an item that has not yet been shown or that has already been disposed; a conformer MAY assume every call it receives corresponds to a currently visible, non-disposed item.
- **remove-tolerates-unknown-id**: `removeStatusBarItem(internalID:)` MUST be safe to call with an `internalID` the conformer never received via `putOrUpdateStatusBarItem(_:)`; a conformer MUST treat this as a no-op rather than raising an error, trapping, or crashing.
- **remove-key-is-internal-id**: `removeStatusBarItem(internalID:)` MUST take the item down using the same `internalID` value carried on the `ExtensionStatusBarItemRequest.internalID` field previously passed to `putOrUpdateStatusBarItem(_:)`; it MUST NOT use `StatusBarItem.id`, the public, non-unique identifier the extension sees.
- **internal-id-not-exposed**: `ExtensionStatusBarItemRequest.internalID` MUST never be surfaced to the extension; it exists solely as the registry and removal key shared between the caller and the presenter.
- **fixed-identity-fields**: `ExtensionStatusBarItemRequest.internalID`, `.id`, `.alignment`, and `.priority` MUST be treated as fixed for the lifetime of one status bar item; the struct declares each `let`, and the caller's own model rebuilds every request from the same immutable values, so a conformer MUST NOT expect any of the four to differ between two calls sharing one `internalID`.
- **mutable-display-fields**: `ExtensionStatusBarItemRequest.name`, `.text`, `.tooltip`, `.color`, `.backgroundColor`, `.command`, `.accessibilityLabel`, and `.accessibilityRole` MUST be free to differ between successive `putOrUpdateStatusBarItem(_:)` calls that share one `internalID`; the struct declares each `var` for exactly this reason.
- **priority-nil-means-undefined**: `ExtensionStatusBarItemRequest.priority` MUST be `nil` when the extension supplied no priority, and MUST NOT be coerced to `0` or any other sentinel numeric value.
- **alignment-two-cases**: `ExtensionStatusBarAlignment` MUST expose exactly two cases, `left` and `right`, corresponding to `vscode.window.StatusBarAlignment`'s `Left` (`1`) and `Right` (`2`); the raw JavaScript numbers MUST map onto these cases nowhere else in the codebase besides `MainThreadWindow.statusBarAlignmentMembers` and `MainThreadWindow.parseAlignment(_:)`.
- **color-flat-string**: `ExtensionStatusBarItemRequest.color` and `.backgroundColor` MUST each be represented as an optional flat `String` id, never as a value that distinguishes a plain string color from a `ThemeColor` id; a conformer MUST NOT expect any richer shape than a single optional string per field.
- **value-equatable**: `ExtensionStatusBarAlignment` and `ExtensionStatusBarItemRequest` MUST both conform to `Equatable`, so a test double or a conformer's own state MAY be compared to an incoming request by value.
- **sendable-value-types**: `ExtensionStatusBarAlignment` and `ExtensionStatusBarItemRequest` MUST both conform to `Sendable`.
- **cross-actor-before-applying**: A conformer MAY move a received `ExtensionStatusBarItemRequest` off the main actor to prepare a view before returning to the main actor to apply it, relying on the type's `Sendable` conformance to cross that boundary safely.
- **designated-initializer**: `ExtensionStatusBarItemRequest` MUST be constructed via its explicit `public init(internalID:id:alignment:priority:name:text:tooltip:color:backgroundColor:command:accessibilityLabel:accessibilityRole:)`; the type MUST NOT rely on Swift's synthesized memberwise initializer, which is `internal` and unusable from the test module that also constructs this type.
- **void-return-no-failure-channel**: `putOrUpdateStatusBarItem(_:)` and `removeStatusBarItem(internalID:)` MUST both return `Void`; the protocol provides no channel through which a conformer can report a presentation failure back to the caller.
- **serialized-calls**: Because both the caller (`MainThreadWindow`, itself `@MainActor`) and the protocol are confined to the main actor, every call into one conformer instance MUST be strictly serialized in the order the caller's method calls and property writes occur; no two calls into the same conformer instance can overlap.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `request` (parameter of `putOrUpdateStatusBarItem`) | `ExtensionStatusBarItemRequest` | none (required) | The full display state of one status bar item to put up or refresh. |
| `internalID` (parameter of `removeStatusBarItem`) | `String` | none (required) | The registry key of the item to take down; safe to pass an id the conformer never received. |
| `ExtensionStatusBarItemRequest.internalID` | `String` | none (required) | Set once by the caller at construction — the extension's supplied id folded with a per-process ordinal, or a bare ordinal when the extension gave none; never shown to the extension. |
| `ExtensionStatusBarItemRequest.id` | `String` | none (required) | The public `StatusBarItem.id` the extension sees; not guaranteed unique across items. |
| `ExtensionStatusBarItemRequest.alignment` | `ExtensionStatusBarAlignment` | none (required) | `.left` or `.right`; fixed for the item's lifetime. |
| `ExtensionStatusBarItemRequest.priority` | `Double?` | `nil` | `nil` means "the extension supplied no priority"; never coerced to `0`. |
| `ExtensionStatusBarItemRequest.name` | `String?` | `nil` | Extension-supplied display name. |
| `ExtensionStatusBarItemRequest.text` | `String` | none (required, caller initializes to `""`) | The item's rendered text; the one field every request always carries a concrete value for. |
| `ExtensionStatusBarItemRequest.tooltip` | `String?` | `nil` | The string form of `StatusBarItem.tooltip`; a `MarkdownString` write is recorded elsewhere as not implemented rather than reaching this field. |
| `ExtensionStatusBarItemRequest.color` / `.backgroundColor` | `String?` | `nil` | The flat id string for either a plain color string or a `ThemeColor`'s `id`; see **color-flat-string**. |
| `ExtensionStatusBarItemRequest.command` | `String?` | `nil` | The string form of `StatusBarItem.command`; a `Command`-object write is likewise recorded elsewhere as not implemented. |
| `ExtensionStatusBarItemRequest.accessibilityLabel` / `.accessibilityRole` | `String?` | `nil` | Extension-supplied `accessibilityInformation` fields, carried through unchanged. |

