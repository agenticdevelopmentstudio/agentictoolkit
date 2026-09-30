<!-- leaf: implement-general-1/delete-entity-section--part-2 · source: delete-entity-section.md -->

# DeleteEntitySection — continued (part 2)

## Shared State

| State | Source | Consumer | Direction | Mechanism |
|---|---|---|---|---|
| `disclosed` (open/closed) | DeleteEntitySection | Disclosure open + red-accent styling | Down | `useState`, controlled `open`/`onOpenChange` |
| `open` (dialog) | DeleteEntitySection | Dialog `open`/`onOpenChange` | Down | `useState` |
| `phase` (`warn`/`confirm`) | DeleteEntitySection | Which dialog body renders | Internal | `useState` |
| `typed` | Input `onChange` | `confirmEnabled` gate | Up then down | `useState`; compared exactly to `confirmValue` |
| `busy` | `handleConfirm` | Button label + dialog lock + close suppression | Down | `useState` |
| `error` | rejected `onConfirm` | Inline error line + `aria-invalid` on the input | Up then down | `useState<string \| null>` |
| delete effect | DeleteEntitySection | Caller `onConfirm` (performs delete + navigation) | Up | `async` callback prop |

## Integration Test Vectors

| ID | Requirements | Input | Expected |
|---|---|---|---|
| T1 | collapse-by-default, accent-red-only-when-disclosed, keep-warning-glyph-gold | Initial render | Disclosure closed, neutral (no red); the ⚠ glyph is gold |
| T2 | accent-red-only-when-disclosed | Open the disclosure | Red border/tint appears and the title text turns red; the ⚠ glyph stays gold |
| T3 | open-warn-phase-first | Click "Delete {entityNoun}" | Dialog opens on the warn phase naming the `childEntities` cascade and asking to proceed |
| T4 | advance-to-confirm-on-yes | Click "Yes" on the warn phase | Dialog advances to type-to-confirm; `onConfirm` not yet called |
| T5 | require-exact-identifier | Type a near-match (wrong case / trailing space) | "Permanently Delete" stays disabled |
| T6 | require-exact-identifier, call-onconfirm-once-enabled | Type the exact `confirmValue`, click Permanently Delete | Button enables; `onConfirm` called once; label shows "Deleting…" |
| T7 | reject-empty-confirm-value | `confirmValue=""`, empty input, reach confirm phase | "Permanently Delete" stays disabled |
| T8 | lock-dialog-while-busy | While `onConfirm` pending, try Escape / close / outside | Dialog stays open; no close affordance is shown |
| T9 | surface-error-inline | `onConfirm` rejects | Error message shows inside the dialog; busy clears; dialog stays open for retry |
| T10 | reset-on-cancel-or-success | Cancel, or resolve `onConfirm` | Dialog closes and resets to empty, warn-phase state |
| T11 | avoid-permanence-claims-when-reversible | `actionVerb={{ imperative: "Archive", gerund: "Archiving", reversible: true }}` with a caller `description`; open, click Yes | Blurb, warn body, and confirm-phase copy all read "Archive"/"Archiving"; no "Permanently", "cannot be undone", or "deletion" anywhere in the flow |
| T12 | avoid-permanence-claims-when-reversible | Same reversible `actionVerb`, `entityNoun="organization"`, no `description` override | The built-in fallback blurb itself reads "Archive this organization. This can be undone later." — no "permanently" or "cannot be undone"; confirm phase shows "Type {confirmValue} to confirm" (no "deletion") |
| T13 | swap-trigger-glyph-when-reversible | Reversible `actionVerb`; open the disclosure | Trigger button renders the `Archive` glyph (`svg.lucide-archive`); no `Trash2` glyph present |
| T14 | swap-trigger-glyph-when-reversible | Default (no `actionVerb`); open the disclosure | Trigger button renders the `Trash2` glyph (`svg.lucide-trash-2`); no `Archive` glyph present |
| T15 | call-onconfirm-once-enabled | Reversible `actionVerb`; reach confirm phase, type the exact `confirmValue`, click the CTA while `onConfirm` is pending | Busy label reads "Archiving…" (from `actionVerb.gerund`), never "Deleting…" |
| T16 | surface-error-inline | Reversible `actionVerb`; `entityNoun="organization"`; `onConfirm` rejects a non-`Error` value | Inline error falls back to "Failed to archive organization." (lowercase `actionVerb.imperative`), since `e.message` never runs for a non-`Error` rejection |
| T17 | disable-actions-while-busy, call-onconfirm-once-enabled | Reach confirm phase with the exact `confirmValue` typed; double-click the confirm CTA in quick succession | `onConfirm` is called exactly once; once `busy` is true both the CTA and Cancel are disabled, so the second click has no enabled target to hit |
| T18 | select-article-from-first-letter | `entityNoun="Ecosystem"`, reach the warn phase | Warn body reads "an ecosystem" |
| T19 | select-article-from-first-letter | `entityNoun="Bucket"`, reach the warn phase | Warn body reads "a bucket" |

## Platform Notes

- **SwiftUI**: Build the collapsed Danger Zone from a `DisclosureGroup(isExpanded:)`
  bound to a `@State` flag equivalent to `disclosed`; recolor only the group's
  label `Text` with `.foregroundStyle(.red)` while `isExpanded` is `true` (the
  `Image(systemName: "exclamationmark.triangle")` warning glyph keeps a fixed gold
  `Color` in both states — see accent-red-only-when-disclosed and
  keep-warning-glyph-gold). Model the two dialog phases as an enum driving
  `.alert(item:)`/`.sheet(item:)` rather than one dialog whose body swaps: the warn
  phase is a plain `.alert` with Cancel/Yes actions, the confirm phase is a
  `.sheet` containing a `TextField` bound to `@State var typed`, with the
  destructive `Button`'s `.disabled(typed != confirmValue || confirmValue.isEmpty)`
  computed as the exact, untrimmed comparison the source uses. Set
  `.interactiveDismissDisabled(busy)` on the confirm sheet to reproduce
  lock-dialog-while-busy, and swap `Image(systemName: "trash")` for
  `"archivebox"` when `actionVerb.reversible` is `true`.
- **Compose**: Use a `Card` with a header `Row` that toggles a
  `rememberSaveable { mutableStateOf(false) }` expanded flag, wrapping the body in
  `AnimatedVisibility`; recolor only the header `Text` with
  `MaterialTheme.colorScheme.error` while expanded, keeping the
  `Icons.Filled.Warning` `Icon` tinted with a fixed gold color in both states.
  Drive the two-phase confirm with two `AlertDialog`s selected by a `phase`
  enum held in `remember` (or a `ViewModel`); the second `AlertDialog`'s
  `confirmButton` sets `enabled = typed.isNotEmpty() && typed == confirmValue`,
  matching the source's exact, untrimmed comparison. While `busy` is `true`, pass
  `onDismissRequest = {}` and omit the dismiss button on the second dialog to
  block dismissal, and swap `Icons.Filled.Delete` for `Icons.Filled.Archive` when
  `actionVerb.reversible` is `true`.
- **React/Web**: `packages/web/packages/adh-ui/src/blocks/delete-entity-section.tsx`
  (`"use client"`), exported via `@agentic-toolkit/adh-ui/blocks/delete-entity-section`.
  Composes `Disclosure`, `Button`, `Dialog` (+ `DialogHeader`/`Title`/`Description`/
  `Footer`), `Input`, and `Label`, with the `Trash2`/`TriangleAlert`/`Archive`
  glyphs from `lucide-react`. Props: `entityNoun`, `confirmValue`, `childEntities`,
  `onConfirm: () => Promise<void>`, optional `description`, and optional
  `actionVerb: { imperative, gerund, reversible? }` (default `{ imperative:
  "Delete", gerund: "Deleting", reversible: false }`, which reproduces today's
  wording byte-for-byte). Demo lives in the `ui-showcase` Topic
  `delete-entity-section` (regenerate `sources.generated.ts` via
  `gen-sources.py` after source changes); verify responsively via Playwright at
  375 / 768 / 1440. Shared across every focused-topic-detail settings route
  (`agentictoolkit://recipes/focused-topic-detail`), usually as the final
  group in a settings pane below the `FieldGroup`s.
- **AppKit/UIKit**: On macOS, build the disclosure from an `NSButton` with
  `bezelStyle = .disclosure` (there is no `NSDisclosureButton` class) toggling a
  subview's `isHidden`, recoloring only the title `NSTextField` with
  `NSColor.systemRed` while expanded. Present the acknowledge phase as an
  `NSAlert` (Cancel/Yes), but present the type-to-confirm phase as its own sheet
  window (`NSWindow` shown via `beginSheet(_:completionHandler:)`) rather than a
  second chained `NSAlert` — `NSAlert.runModal` cannot represent an async busy
  state (a disabled CTA with a "Deleting…" label) or a suppressed close control,
  which a sheet's own view controller can. The sheet carries an `NSTextField`
  whose delegate (`controlTextDidChange`) enables the confirm `NSButton` only on
  an exact `String` equality against `confirmValue`, and disables both that
  button and its Cancel button while busy. The two dialogs are never open at
  once: the acknowledge `NSAlert` must finish (and be dismissed) before the
  confirm sheet is presented. On iOS, use a collapsible `UIStackView` section and
  a chained `UIAlertController` (`.alert`) for the acknowledge phase, then a
  second `UIAlertController` built with `addTextField` and a
  `.textDidChangeNotification` observer that gates the confirm `UIAlertAction`'s
  `isEnabled` the same way, disabling both actions while busy. Block dismissal
  while busy by setting `isModalInPresentation = true` (iOS) or omitting the
  sheet's close control (macOS) until the async delete settles, and swap the
  trash `UIImage`/`NSImage` (`systemName: "trash"`) for `"archivebox"` when
  `actionVerb.reversible` is `true`.
- **WinUI 3**: Use an `Expander` (`IsExpanded="{x:Bind Disclosed, Mode=TwoWay}"`)
  for the Danger Zone, collapsed by default. Bind the `Header` `TextBlock`'s
  `Foreground` to a `SolidColorBrush` resource selected by a
  `VisualStateManager` state (`Disclosed` / `Collapsed`) so the red accent brush
  applies only while expanded — never a converter on the warning icon, whose
  `FontIcon.Foreground` stays a fixed gold brush in both states (see
  accent-red-only-when-disclosed and keep-warning-glyph-gold). Trigger a
  `ContentDialog` for the acknowledge phase (`PrimaryButtonText="Yes"`,
  `CloseButtonText="Cancel"`), then a second `ContentDialog` with a `TextBox`
  whose `TextChanged` handler sets `IsPrimaryButtonEnabled` from
  `string.Equals(textBox.Text, confirmValue, StringComparison.Ordinal) &&
  confirmValue.Length > 0` (reproducing require-exact-identifier and
  reject-empty-confirm-value). The two `ContentDialog`s are never shown
  concurrently: the acknowledge dialog's `Hide()` completes before the confirm
  dialog is shown. In the `PrimaryButtonClick` handler, call
  `args.GetDeferral()` before awaiting the delete, set
  `IsPrimaryButtonEnabled = false` and swap the button content for a
  `ProgressRing` plus "Deleting…" text while the call is pending — a
  `ContentDialog` otherwise stays light-dismissible during an async
  `PrimaryButtonClick`, so the deferral is what reproduces
  lock-dialog-while-busy. On success, call `deferral.Complete()` to let the
  dialog close. On failure, bind a `TextBlock` to the caught message and make it
  visible, set `args.Cancel = true` to keep the dialog open, then call
  `deferral.Complete()` — completing the deferral either way is required, since
  leaving it pending wedges the dialog; `args.Cancel = true` is what actually
  keeps it open for retry (surface-error-inline). Swap
  the `FontIcon` glyph from the Segoe Fluent Icons trash glyph (`\uE74D`) to the
  archive glyph (`\uE7B8`) when `actionVerb.reversible` is `true`.

