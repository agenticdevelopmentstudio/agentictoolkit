<!-- leaf: implement-extension-host-vs-presenting/code-api-extension-quick-pick-presenting--part-2 · source: extension-host-vs-code-api-extension-quick-pick-presenting.md -->

# ExtensionQuickPickPresenting — continued (part 2)

**Rules** (cite as `implement-extension-host-vs-presenting/code-api-extension-quick-pick-presenting--part-2#<slug>`):

- `decision` MUST — nil means the picker was dismissed; [] (only reachable when canPickMany is true) means the user explicitly accepted a …
- `decision-2` MUST — constructing an ExtensionQuickPickItem for a separator row (isSeparator == true) MUST set description, detail, …

## Platform Notes

- **SwiftUI**: not this file's own dependency — `ExtensionQuickPickPresenting.swift` imports only `Foundation`, with no SwiftUI reference. A SwiftUI-hosted picker would need its own concrete conformer (the role `ExtensionPickerPresenter` plays for AppKit), but the protocol and its two data types are UI-framework agnostic and would not change.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionQuickPickPresenting.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is `@MainActor`-isolated per its own declaration, and its production conformer among the given sources, `ExtensionPickerPresenter` (`macOS/Features/Extensions/UI/ExtensionPickerPresenter.swift`), is an AppKit window/view-controller-backed panel that also conforms to `ExtensionInputBoxPresenting`.
- **Compose**: model this as a Kotlin `interface ExtensionQuickPickPresenting` with `suspend fun presentQuickPick(request: ExtensionQuickPickRequest, onHighlight: (Int) -> Unit): List<Int>?`, confined to the main dispatcher (`Dispatchers.Main.immediate`) in place of `@MainActor`; `ExtensionQuickPickItem`/`ExtensionQuickPickRequest` become Kotlin `data class`es, whose structural equality already gives `Equatable` and whose immutability already gives `Sendable`'s guarantee across coroutine dispatch. `List<Int>?`'s `null` vs `emptyList()` distinction maps the `nil`-vs-`[]` contract directly.
- **React/Web**: model as a TypeScript `interface ExtensionQuickPickPresenting { presentQuickPick(request: ExtensionQuickPickRequest, onHighlight: (index: number) => void): Promise<number[] | undefined> }`; `undefined` vs `[]` is the same distinction JavaScript's own `showQuickPick` promise already makes (`extHostQuickOpen.ts`'s `handle.map(...)` resolving `[]` rather than `undefined`), so no adapter is needed for that part of the contract. `ExtensionQuickPickItem`/`ExtensionQuickPickRequest` become plain `interface`s (or `readonly` object types) rather than classes, since there is no initializer-visibility concern to solve on this platform.
- **WinUI 3**: model `ExtensionQuickPickPresenting` as `public interface IExtensionQuickPickPresenting { Task<IReadOnlyList<int>?> PresentQuickPickAsync(ExtensionQuickPickRequest request, Action<int> onHighlight, CancellationToken cancellationToken = default); }`, called only from the UI thread (the `DispatcherQueue` a WinUI 3 window owns, in place of `@MainActor`); a nullable `IReadOnlyList<int>?` gives the same `null`-vs-empty-collection distinction as `[Int]?` without a wrapper type. `ExtensionQuickPickItem` and `ExtensionQuickPickRequest` become `sealed record`s (`record ExtensionQuickPickItem(string Label, string? Description, string? Detail, bool IsSeparator, bool IsPicked, bool AlwaysShow)`), whose generated value-based `Equals`/`GetHashCode` gives `Equatable`'s guarantee, and whose immutability gives the same cross-thread-handoff safety `Sendable` states explicitly on the Swift side. `System.Text.Json` has no role here since nothing in this file serializes; it is Windows App SDK's own extension-host bridge (analogous to `MainThreadWindow`) that would decode the incoming request before constructing these types.

## Design Decisions

**Decision**: `ExtensionQuickPickPresenting` is a separate protocol from `ExtensionMessagePresenting`, rather than one protocol carrying both members.
**Rationale**: per the source's own doc comment, `NSAlertMessagePresenter` is the right conformer for a message and the wrong one for a picker; a single combined protocol would force a message-only conformer to implement a presentation it has no business showing — interface segregation, at the declared cost that `MainThreadWindow.init` takes two presenters rather than one.
**Approved**: pending

**Decision**: `nil` means the picker was dismissed; `[]` (only reachable when `canPickMany` is `true`) means the user explicitly accepted a selection of nothing. The two MUST NOT be conflated.
**Rationale**: upstream's `handle.map(...)` of an empty handle array resolves `[]` rather than `undefined` (`extHostQuickOpen.ts`); a conformer that answered `[]` for a dismissal would tell the extension the user accepted an empty selection, a different, observable answer to code doing `if (result === undefined)`.
**Approved**: pending

**Decision**: single-select and multi-select both answer through the same `[Int]?` return type — a one-element array for single-select — rather than two overloads (a bare `Int?` for single-select, `[Int]?` for multi-select).
**Rationale**: `canPickMany` is a field of the request every conformer already reads; two overloads would make each conformer spell the dismissal rule (`nil` vs `[]`) twice instead of once, per the source's own doc comment.
**Approved**: pending

**Decision**: `ExtensionQuickPickItem` carries no `iconPath`, `resourceUri`, or `buttons` field, even though `QuickPickItem` declares all three.
**Rationale**: per the struct's own doc comment, `buttons` is dropped because the VS Code declaration states buttons are "not rendered when using the `showQuickPick` API" at all; `iconPath` and `resourceUri` are dropped because nothing in this repo resolves an extension-supplied icon path to an image, and a field that is always dropped reads to the next person as a capability that exists when it does not — worse than the field's absence.
**Approved**: pending

**Decision**: constructing an `ExtensionQuickPickItem` for a separator row (`isSeparator == true`) MUST set `description`, `detail`, `isPicked`, and `alwaysShow` to their defaults regardless of what the extension supplied for them.
**Rationale**: quoting the source's own doc comment on `isSeparator`, "The only property that applies is `QuickPickItem.label`. All other properties on `QuickPickItem` will be ignored and have no effect," per `vscode.d.ts`.
**Approved**: pending

**Decision**: `isPicked` and `alwaysShow` are carried truthfully regardless of `canPickMany` or the current filter text; applying VS Code's own conditions for honoring them ("only honored when the picker allows multiple selections" for `picked`; keeping a row visible despite the filter for `alwaysShow`) is deferred to the presenting conformer or, for `alwaysShow`, to `ExtensionQuickPickModel.matches(_:filter:)`.
**Rationale**: per the source's own doc comment, a type that zeroed `isPicked` out itself would leave the presenter unable to tell "the extension did not ask for this row" from "the extension asked and something upstream discarded it"; the rule for when a flag is *honored* is a presentation concern, not a parsing concern.
**Approved**: pending
