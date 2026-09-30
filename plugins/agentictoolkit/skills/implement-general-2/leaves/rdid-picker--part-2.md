<!-- leaf: implement-general-2/rdid-picker--part-2 · source: rdid-picker.md -->

# RdidPicker — continued (part 2)

## Platform Notes

- **React/Web (source)**: `packages/web/packages/adh-ui/src/blocks/rdid-picker.tsx`
  (`@agentic-toolkit/adh-ui`, `"use client"`). Composes `CommandPalette` and
  `CommandGroup` from `@agenticdevelopertoolkit/ui/blocks/command-palette`;
  `RdidPicker` itself owns only the debounce/abort/reset state machine and
  the group/label/placeholder derivation — no dialog, listbox, or keyboard
  logic of its own.
- **SwiftUI**: Present as a `.sheet`/`.popover` hosting a `List` with a
  `.searchable(text:)`-bound query; drive the debounced fetch from a
  `.task(id: query)` after a `Task.sleep(for:)` of `debounceMs` — a new
  `id` automatically cancels the prior `Task`, giving abort-on-supersede for
  free without a manual `AbortController` analogue. Surface `loading`/`error`
  as an overlay (`ProgressView`, `ContentUnavailableView`) over the `List`.
- **Compose**: Host in a `ModalBottomSheet` or `AlertDialog` with a
  `LazyColumn`; bind the search `TextField` through a `Flow` using
  `.debounce(debounceMs)` and `.collectLatest { }`, which mirrors the
  trailing-delay-plus-cancel-on-supersede this ingredient implements by hand with
  `setTimeout`/`AbortController`. Hoist `loading`/`error`/`options` as Compose
  state the same way `query`/`options` are hoisted here.
- **AppKit/UIKit**: Present modally (`NSPanel` or a `UIViewController`) over
  an `NSSearchField`/`UISearchController` and a table view. Debounce by
  rescheduling a single `DispatchWorkItem`/`Timer` on every keystroke (cancel
  and replace, matching the `clearTimeout`+new `setTimeout` here), and cancel
  the in-flight `URLSessionTask` the way `AbortController.abort()` is called
  here before starting the next one.
- **WinUI 3**: Use an `AutoSuggestBox` inside a `ContentDialog` (or a
  `Popup`) as the direct analogue of `CommandPalette`'s combobox input +
  listbox pairing — `AutoSuggestBox` already binds a text box to a
  keyboard-navigable suggestion list with Enter-to-commit, matching the
  type/arrow/Enter contract this ingredient requires. Bind `ItemsSource` to a
  small view-model list exposing `Rdid`/`EntityType` for the item template's
  primary text and badge (mirroring `renders-each-result-by-rdid-with-badge`).
  Debounce in the `TextChanged` handler with a `DispatcherTimer` that is
  stopped and restarted on every keystroke (the `setTimeout` reset here), and
  cancel the previous lookup via a stored `CancellationTokenSource.Cancel()`
  before creating a new one and awaiting `SearchAsync(query, token)` — the
  direct analogue of `AbortController`. Bind `IsLoading` to show a
  `ProgressRing` (or the `AutoSuggestBox`'s built-in loading indicator) and
  bind an `ErrorMessage` string to a status `TextBlock`, toggled exactly as
  `loading`/`error` gate `CommandPalette`'s render here. Clear
  `AutoSuggestBox.Text` and the bound `ItemsSource` in the dialog's `Closing`
  handler, mirroring the `open`-keyed reset effect in source.

## Design Decisions

- **Decision**: Build on `CommandPalette` rather than a bespoke search
  dialog.
  **Rationale**: Per source comment in `rdid-picker.tsx`'s top-of-file JSDoc,
  "the palette already IS this interaction — a modal over one field,
  keyboard-driven, first result preselected, Enter runs it and closes." A
  second dialog with its own search box and result list would duplicate that
  shape under a different name.
  **Approved**: pending
- **Decision**: No `scope` prop; a caller restricts results by closing over
  its own filter inside `search`.
  **Rationale**: Per source comment in `rdid-picker.tsx`'s top-of-file JSDoc
  ("SCOPING IS THE CALLER'S" paragraph), a `scope` prop would mean this
  component owns the list of scopes, requiring every new entity type to come
  back and edit it; closing over the filter keeps `RdidPicker` ignorant of
  what an "ecosystem" (or any other entity type) is.
  **Approved**: pending
- **Decision**: Debouncing and abort-on-supersede live in `RdidPicker`, not
  in `CommandPalette`.
  **Rationale**: Per source comment in `rdid-picker.tsx`'s top-of-file JSDoc
  ("DEBOUNCING LIVES HERE" paragraph), `CommandPalette` is a controlled input
  with no opinion on when the host fetches; but this picker's list IS the
  fetch, so the trailing delay and the abort of a superseded request belong
  to it.
  **Approved**: pending
- **Decision**: `onPick` receives the whole `RdidOption`, not just the
  `rdid` string.
  **Rationale**: Per source comment on the `onPick` prop in
  `rdid-picker.tsx`, a caller that needs the entity id must not have to
  re-resolve the address it just picked — a second lookup that can disagree
  with the first.
  **Approved**: pending
- **Decision**: `search` is read through a ref (`searchRef`) inside the
  debounce effect instead of listing `search` itself as a dependency.
  **Rationale**: Per source comment above the `searchRef` effect in
  `rdid-picker.tsx`, `search` is usually an inline arrow function with a new
  identity on every render; keying the effect on it would restart the
  debounce on every parent re-render, and a steadily typing user would never
  reach the trailing edge.
  **Approved**: pending
- **Decision**: Closing the picker clears `query`, `options`, `error`, and
  `loading`.
  **Rationale**: Per source comment above the close-triggered reset effect in
  `rdid-picker.tsx`, reopening onto a stale query and a stale list would
  offer a result for a search the user has already moved on from.
  **Approved**: pending
- **Decision**: A failed search clears `options` rather than leaving stale
  results in place.
  **Rationale**: Per source comment in the rejection handler in
  `rdid-picker.tsx`, an empty list after a failed request reads as "no such
  address," the one wrong conclusion available; clearing `options` and
  setting `error` avoids that misreading.
  **Approved**: pending
- **Decision**: Only `title`, `placeholder`, and `entityTypeLabel` are
  caller-overridable strings; the group label's "addresses" suffix, both
  empty-state labels, and the non-`Error` rejection fallback ("Search
  failed") are fixed English literals with no localization mechanism.
  **Rationale**: `rdid-picker.tsx` exposes no other string-customization
  prop and contains no localization key extraction or i18n call; this is the
  component's current, deliberate string surface rather than an oversight,
  and any broader localization would need to be added as new props.
  **Approved**: pending
