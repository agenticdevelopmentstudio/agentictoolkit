<!-- leaf: implement-extension-host-vs-presenting/code-api-extension-quick-pick-presenting · source: extension-host-vs-code-api-extension-quick-pick-presenting.md -->

**Rules** (cite as `implement-extension-host-vs-presenting/code-api-extension-quick-pick-presenting#<slug>`):

- `item-sendable-equatable` MUST
- `item-label-required` MUST
- `item-description-optional` MUST
- `item-detail-optional` MUST
- `item-separator-flag` MUST
- `item-separator-fields-defaulted` MUST
- `item-picked-flag` MUST
- `item-always-show-flag` MUST
- `item-explicit-initializer` MUST
- `request-sendable-equatable` MUST
- `request-optional-text-fields` MUST
- `request-items-order-preserved` MUST
- `request-can-pick-many-flag` MUST
- `request-match-flags` MUST
- `request-ignore-focus-out-flag` MUST
- `request-explicit-initializer` MUST
- `presenting-main-actor-isolation` MUST
- `presenting-class-only` MUST
- `presenting-single-requirement` MUST
- `presenting-index-based-answer` MUST
- `presenting-dismissal-is-nil` MUST
- `presenting-empty-selection-is-not-dismissal` MUST
- `presenting-single-select-array-shape` MUST
- `presenting-answer-order-preserved` MUST
- `presenting-highlight-index` MUST
- `presenting-highlight-frequency` MAY
- `presenting-highlight-after-return-prohibited` MUST
- `presenting-async-return` MUST

# ExtensionQuickPickPresenting

## Overview

`ExtensionQuickPickPresenting.swift` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionQuickPickPresenting.swift`) declares the extension-host's contract for one `vscode.window.showQuickPick` call: two `Sendable, Equatable` data types, `ExtensionQuickPickItem` and `ExtensionQuickPickRequest`, that reduce a `QuickPickItem`/`QuickPickOptions` call to what a presenter needs, and the `@MainActor` protocol `ExtensionQuickPickPresenting` that a presenter conforms to in order to actually put a picker on screen (or, in a test, record what it was asked to show). Per the file's own header comment, it was split out of `MainThreadWindow.swift` once that file grew past 2,800 lines — a file-boundary split, not a tier split, and `MainThreadWindow` remains this contract's only caller among the given sources. `ExtensionPickerPresenter` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/ExtensionPickerPresenter.swift`) is the production conformer; it also conforms to the sibling `ExtensionInputBoxPresenting` protocol, one AppKit panel serving both seams. The protocol is declared separately from `ExtensionMessagePresenting`, deliberately, on an interface-segregation rationale documented directly in the source (see Design Decisions).

## Behavioral Requirements

- **item-sendable-equatable**: `ExtensionQuickPickItem` MUST conform to `Sendable` and `Equatable`.
- **item-label-required**: `ExtensionQuickPickItem.label` MUST be a non-optional `String`; it is the only property that applies to a row for which `isSeparator` is `true`.
- **item-description-optional**: `ExtensionQuickPickItem.description` MUST be `nil` when the item carried no description, or carried one that was not a string; when non-`nil` it is rendered less prominently on the same line as `label`.
- **item-detail-optional**: `ExtensionQuickPickItem.detail` MUST be `nil` on the same terms as `description`; when non-`nil` it is rendered less prominently on a separate line.
- **item-separator-flag**: `ExtensionQuickPickItem.isSeparator` MUST be `true` only for a row whose upstream `kind` was `QuickPickItemKind.Separator` (the number `-1`); every other row MUST report `false`.
- **item-separator-fields-defaulted**: When `isSeparator` is `true`, `description`, `detail`, `isPicked`, and `alwaysShow` MUST each be constructed at their default (`nil`, `nil`, `false`, `false`) regardless of what values the extension supplied for them, because only `label` applies to a separator row.
- **item-picked-flag**: `ExtensionQuickPickItem.isPicked` MUST report the item's truthy `picked` value exactly as supplied, independent of the owning request's `canPickMany` value; applying `picked`'s "only honored when the picker allows multiple selections" rule is the presenting conformer's responsibility, not this type's.
- **item-always-show-flag**: `ExtensionQuickPickItem.alwaysShow` MUST report the item's truthy `alwaysShow` value exactly as supplied; keeping the row visible despite an active filter is the presenting conformer's or model's responsibility, not this type's.
- **item-explicit-initializer**: `ExtensionQuickPickItem` MUST declare an explicit `public init(label:description:detail:isSeparator:isPicked:alwaysShow:)` rather than relying on the compiler-synthesized memberwise initializer, so a test in another module can construct one.
- **request-sendable-equatable**: `ExtensionQuickPickRequest` MUST conform to `Sendable` and `Equatable`.
- **request-optional-text-fields**: `ExtensionQuickPickRequest.title`, `.placeHolder`, and `.prompt` MUST each be `nil` when the extension supplied none for the corresponding `QuickPickOptions` field.
- **request-items-order-preserved**: `ExtensionQuickPickRequest.items` MUST preserve the extension-supplied order, separators included at their original positions; the indices a conforming presenter answers are positions into this exact array.
- **request-can-pick-many-flag**: `ExtensionQuickPickRequest.canPickMany` MUST report whether the user may accept more than one row.
- **request-match-flags**: `ExtensionQuickPickRequest.matchOnDescription` and `.matchOnDetail` MUST each report the caller-supplied filtering flag for that field, independent of one another.
- **request-ignore-focus-out-flag**: `ExtensionQuickPickRequest.ignoreFocusOut` MUST report whether the picker should stay open when focus moves elsewhere.
- **request-explicit-initializer**: `ExtensionQuickPickRequest` MUST declare an explicit `public init(title:placeHolder:prompt:items:canPickMany:matchOnDescription:matchOnDetail:ignoreFocusOut:)`, for the same cross-module-testability reason as `ExtensionQuickPickItem`.
- **presenting-main-actor-isolation**: `ExtensionQuickPickPresenting` MUST be declared `@MainActor`; every conformer's `presentQuickPick` call MUST execute on the main actor.
- **presenting-class-only**: `ExtensionQuickPickPresenting` MUST constrain conformers to `AnyObject`; a value type MUST NOT be able to conform.
- **presenting-single-requirement**: `ExtensionQuickPickPresenting` MUST declare exactly one requirement, `presentQuickPick(_:onHighlight:)`.
- **presenting-index-based-answer**: A conformer's non-dismissed answer MUST be indices into the `request.items` array it was given, never labels or copies of the items; two items sharing a `label` MUST remain distinguishable by position alone.
- **presenting-dismissal-is-nil**: A conformer MUST answer `nil` when, and only when, the user dismissed the picker without accepting a selection.
- **presenting-empty-selection-is-not-dismissal**: When `request.canPickMany` is `true` and the user explicitly accepts a selection of zero rows, a conformer MUST answer `[]`; `nil` and `[]` MUST NOT be conflated.
- **presenting-single-select-array-shape**: A conformer's non-dismissed answer MUST be typed `[Int]?` regardless of `request.canPickMany`; when `request.canPickMany` is `false`, a non-dismissed answer MUST contain exactly one element.
- **presenting-answer-order-preserved**: The order of indices in a conformer's non-dismissed answer MUST be the order the selection is to be reported to the extension; it MUST NOT be reordered (for example, sorted) downstream.
- **presenting-highlight-index**: Each `onHighlight` invocation MUST pass an index into `request.items` corresponding to the row newly highlighted.
- **presenting-highlight-frequency**: `onHighlight` MAY be invoked any number of times, including zero, over the lifetime of one `presentQuickPick` call.
- **presenting-highlight-after-return-prohibited**: A conformer MUST NOT invoke `onHighlight` after its `presentQuickPick` call has returned.
- **presenting-async-return**: `presentQuickPick` MUST be an `async` function that suspends until the picker session concludes — accepted or dismissed — before returning.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `request` | `ExtensionQuickPickRequest` | none (required) | The whole call's input to `presentQuickPick`; a conformer reads it to build what it shows. |
| `onHighlight` | `@escaping (Int) -> Void` | none (required) | Invoked by the conformer with an index into `request.items` each time the highlighted row changes. |
| `request.title` | `String?` | `nil` | `QuickPickOptions.title`. |
| `request.placeHolder` | `String?` | `nil` | `QuickPickOptions.placeHolder`; filter-field placeholder text. |
| `request.prompt` | `String?` | `nil` | `QuickPickOptions.prompt`; carried but read by nothing this file's own consumer builds. |
| `request.items` | `[ExtensionQuickPickItem]` | none (required) | The rows to present, in extension-supplied order, separators included. |
| `request.canPickMany` | `Bool` | none (required) | `QuickPickOptions.canPickMany`; whether more than one row may be accepted. |
| `request.matchOnDescription` | `Bool` | none (required) | `QuickPickOptions.matchOnDescription`; whether `description` participates in filtering (documented upstream default `false`). |
| `request.matchOnDetail` | `Bool` | none (required) | `QuickPickOptions.matchOnDetail`; whether `detail` participates in filtering (documented upstream default `false`). |
| `request.ignoreFocusOut` | `Bool` | none (required) | `QuickPickOptions.ignoreFocusOut`; whether the picker stays open when focus moves elsewhere. |

## Privacy

- **Data collected**: `ExtensionQuickPickPresenting.swift` collects no data of its own; `ExtensionQuickPickItem` and `ExtensionQuickPickRequest` hold only values the calling extension already supplied for that one presentation.
- **Storage**: not applicable — this file performs no storage; a value exists only for the duration of one `presentQuickPick` call.
- **Transmission**: not applicable — this file transmits nothing itself; it is presented on-device by whatever conformer is in use.
- **Retention**: this file retains nothing beyond the lifetime of one `presentQuickPick` call's local state.

