<!-- leaf: implement-extension-host-vs-presenting/code-api-extension-message-presenting · source: extension-host-vs-code-api-extension-message-presenting.md -->

**Rules** (cite as `implement-extension-host-vs-presenting/code-api-extension-message-presenting#<slug>`):

- `severity-cases` MUST
- `severity-value-semantics` MUST
- `request-stored-shape` MUST
- `request-sendable-only` MUST
- `request-module-private-construction` MUST
- `close-affordance-indices-are-a-list` MUST
- `close-affordance-indices-empty-default` MUST
- `close-affordance-indices-within-item-bounds` MUST
- `presenting-protocol-isolation` MUST
- `presenting-protocol-class-only` MUST
- `presenting-single-operation` MUST
- `present-message-return-index` MUST
- `present-message-return-nil-on-dismiss` MUST
- `present-message-empty-items-always-nil` MUST
- `present-message-no-throwing-path` MUST
- `is-modal-carried-not-enforced` MUST
- `detail-optional-presentation` MAY

# ExtensionMessagePresenting

## Overview

`ExtensionMessagePresenting` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionMessagePresenting.swift`) is the seam a `vscode.window.show*Message` call is reduced to before anything AppKit-specific gets involved. The file defines three things: `ExtensionMessageSeverity`, an enum for which of the three `show*Message` calls (`showInformationMessage`, `showWarningMessage`, `showErrorMessage`) produced the request; `ExtensionMessageRequest`, a `Sendable` value carrying everything a presenter needs to show something and report back which button — if any — the user chose; and `ExtensionMessagePresenting` itself, a `@MainActor`, class-only protocol with one method, `presentMessage(_:) async -> Int?`. Per the file's own header comment, it was split out of `MainThreadWindow.swift` once that adaptor grew past 2,800 lines — a file boundary, not a tier boundary, since `MainThreadWindow` remains the seam's only consumer of the protocol and its argument-parsing/promise-settlement logic is what the split keeps testable without AppKit. The one production conformer given among the sources, `NSAlertMessagePresenter`, presents a request with `NSAlert` as an app-modal-avoiding sheet; this recipe documents the contract that conformer (and any other) must satisfy, not that conformer's own presentation choices, except where the request struct's own doc comments describe an invariant a conformer is required to honor.

## Behavioral Requirements

- **severity-cases**: `ExtensionMessageSeverity` MUST expose exactly three cases — `information`, `warning`, and `error` — one per `vscode.window.show*Message` call kind.
- **severity-value-semantics**: `ExtensionMessageSeverity` MUST conform to `Sendable` and `Equatable`, and MUST carry no associated value on any case.
- **request-stored-shape**: `ExtensionMessageRequest` MUST carry exactly six immutable stored properties: `severity` (`ExtensionMessageSeverity`), `message` (`String`), `detail` (`String?`), `isModal` (`Bool`), `itemTitles` (`[String]`), and `closeAffordanceIndices` (`[Int]`).
- **request-sendable-only**: `ExtensionMessageRequest` MUST conform to `Sendable`; the source declares no `Equatable` conformance for it, so two request values MUST NOT be compared with a built-in `==` — a caller that needs equality must compare individual fields itself.
- **request-module-private-construction**: because the source declares no explicit `public init` for `ExtensionMessageRequest`, its Swift-synthesized memberwise initializer MUST remain at internal access; a caller outside the compiling module (`AgenticToolkitMacOS`) MUST NOT be able to construct an `ExtensionMessageRequest` value directly.
- **close-affordance-indices-are-a-list**: `closeAffordanceIndices` MUST hold every index into `itemTitles` whose corresponding message item carried a truthy `isCloseAffordance`, in item order, as a list rather than a single optional index, so that more than one flagged item is representable.
- **close-affordance-indices-empty-default**: `closeAffordanceIndices` MUST be empty when no item in `itemTitles` was flagged `isCloseAffordance`.
- **close-affordance-indices-within-item-bounds**: every value in `closeAffordanceIndices` MUST be a valid index into `itemTitles`; `ExtensionMessageRequest` performs no bounds check of its own, so upholding this invariant MUST be the responsibility of whatever constructs the request.
- **presenting-protocol-isolation**: `ExtensionMessagePresenting` MUST be declared `@MainActor`, so a conforming type's stored-property access and the synchronous portion of `presentMessage(_:)` MUST run on the main actor.
- **presenting-protocol-class-only**: `ExtensionMessagePresenting` MUST constrain conformers to `AnyObject`; a value type MUST NOT conform to it.
- **presenting-single-operation**: `ExtensionMessagePresenting` MUST declare exactly one requirement, `presentMessage(_ request: ExtensionMessageRequest) async -> Int?`, and MUST supply no default implementation for it.
- **present-message-return-index**: when the user chooses an item, `presentMessage(_:)` MUST return the index of that item into `request.itemTitles`.
- **present-message-return-nil-on-dismiss**: `presentMessage(_:)` MUST return `nil` when the user dismissed the message without choosing an item.
- **present-message-empty-items-always-nil**: `presentMessage(_:)` MUST return `nil` whenever `request.itemTitles` is empty, regardless of how the message was dismissed, because there is no item to choose.
- **present-message-no-throwing-path**: `presentMessage(_:)` MUST NOT throw; the protocol defines no error case, so a conformer that cannot present the message at all MUST resolve the call the same way as a user dismissal, `nil`, rather than signal the failure by any other means.
- **is-modal-carried-not-enforced**: `isModal` MUST be carried on `ExtensionMessageRequest` exactly as supplied; `ExtensionMessagePresenting` places no requirement on whether, or how, a conformer's presentation honors it.
- **detail-optional-presentation**: a conformer MAY omit presenting `detail` in its own surface when it is `nil`; the protocol imposes no non-nil or minimum-length constraint on either `message` or `detail`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `severity` | `ExtensionMessageSeverity` | none (required) | Which `show*Message` call produced this request. |
| `message` | `String` | none (required) | The primary text to present; no length or emptiness constraint. |
| `detail` | `String?` | none (required argument; `nil` denotes "no detail") | Optional secondary text. |
| `isModal` | `Bool` | none (required) | The caller's stated modality preference; carried but not enforced, per **is-modal-carried-not-enforced**. |
| `itemTitles` | `[String]` | none (required; empty array denotes no buttons) | Button titles in display order; also the domain `presentMessage(_:)`'s returned index is drawn from. |
| `closeAffordanceIndices` | `[Int]` | none (required; empty array denotes no flagged items) | Indices into `itemTitles` whose item the extension flagged `isCloseAffordance`. |

## Privacy

- **Data collected**: `ExtensionMessagePresenting.swift` collects nothing on its own; `message`, `detail`, and `itemTitles` are whatever text the calling extension supplied to a `vscode.window.show*Message` call, held only as the fields of one `ExtensionMessageRequest` value for the lifetime of a single `presentMessage(_:)` call.
- **Storage**: the file performs no storage of its own; nothing here persists a request beyond the call it was built for.
- **Transmission**: the file performs no network transmission; the request value is passed in-process, from whatever constructs it to whichever conformer presents it.
- **Retention**: no value defined here outlives the `presentMessage(_:)` call it was constructed for; the type keeps no cache, log, or history of past requests.

## Platform Notes

- **SwiftUI**: SwiftUI has no single API that both renders a button and marks it "the cancel one" the way `NSAlert.addButton(withTitle:)` plus a manually-assigned key equivalent does, so a SwiftUI port of a conformer would need its own `buttonPlan`-equivalent function (mirroring `NSAlertMessagePresenter.buttonPlan(for:)`) feeding a `ForEach` over `.alert(_:isPresented:actions:)` actions, deciding per action whether it gets the `.cancel` role or an ordinary button role.
- **Compose**: model `ExtensionMessagePresenting` as a Kotlin `interface ExtensionMessagePresenting { suspend fun presentMessage(request: ExtensionMessageRequest): Int? }` confined to the main dispatcher — the `@MainActor` equivalent — and `ExtensionMessageRequest`/`ExtensionMessageSeverity` as a Kotlin `data class`/`enum class`; a `data class` gives structural `equals`/`hashCode` for free, unlike the Swift struct, which a port should decide whether to suppress to match **request-sendable-only**. A Compose conformer would use `AlertDialog`'s `confirmButton`/`dismissButton` slots for up to two buttons and a manually built list for anything beyond that, since `AlertDialog` has no built-in N-button layout.
- **React/Web**: model the protocol as an async function `presentMessage(request: ExtensionMessageRequest): Promise<number | null>`, and the data shapes as a TypeScript `type`/`interface`; TypeScript has no compiler-enforced actor isolation, so **presenting-protocol-isolation** becomes a convention — call and resolve on the same JS execution context that owns the UI — rather than something the compiler checks. A browser conformer builds its own modal (a native `dialog` element or a design-system modal) rendering one button per `buttonPlan`-equivalent entry, since neither `window.confirm` nor `window.alert` supports more than a fixed OK/Cancel pair.
- **AppKit / UIKit**: this is the source. `ExtensionMessagePresenting.swift` and its one given conformer, `NSAlertMessagePresenter.swift` (both in `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/`), belong to the `AgenticToolkitMacOS` framework target; the conformer uses `NSAlert` and `beginSheetModal(for:completionHandler:)` bridged into `async` with `withCheckedContinuation`. A UIKit iOS port would use `UIAlertController` with an array of `UIAlertAction`s and `present(_:animated:completion:)`; because an iOS app is always foreground, the "no window anywhere, drop the message" fallback `NSAlertMessagePresenter.presentedResponse(for:)` implements has a much narrower analogue there — a root view controller that has not yet attached.
- **WinUI 3**: model `ExtensionMessagePresenting` as `public interface IExtensionMessagePresenting { Task<int?> PresentMessageAsync(ExtensionMessageRequest request); }`, called only on the `DispatcherQueue` a `@MainActor` maps to (marshalling any off-thread call through `DispatcherQueue.TryEnqueue`). `ExtensionMessageRequest` becomes a `public sealed record ExtensionMessageRequest(ExtensionMessageSeverity Severity, string Message, string? Detail, bool IsModal, IReadOnlyList<string> ItemTitles, IReadOnlyList<int> CloseAffordanceIndices)`, and `ExtensionMessageSeverity` a plain `enum`. A WinUI 3 conformer presents with `ContentDialog`, whose `PrimaryButtonText`/`SecondaryButtonText`/`CloseButtonText` give exactly three button slots — fewer than `NSAlert`'s unbounded button list — so a request needing more than three effective buttons (after the same last-wins cancel-slot collapse **close-affordance-indices-are-a-list** requires) needs either a custom `ContentDialog` body with its own `StackPanel` of `Button`s wired to close the dialog with a result, or `Windows.UI.Popups.MessageDialog` with its own capped `UICommand` list; either way the port must reimplement `buttonPlan(for:)`'s skip-and-collapse logic itself. `Task`/`async`/`await` plays the role of Swift's `async`; `CancellationToken` has no counterpart to wire up here, per the Edge Cases entry on cancellation.

