<!-- leaf: implement-general-1/htdv-engine--part-5 · source: htdv-engine.md -->

# HTDV Engine — continued (part 5)

## Privacy

- **Data collected**: None of the given sources collect data on their own;
  `FormState`/`FormValidator` operate only on whatever field values the
  host's form spec asks the user to enter (arbitrary `String`/`Bool`/
  `Double`/`Date`/`[String]`, per `FormValue`'s shape) — the engine itself
  has no knowledge of whether any given key is sensitive.
- **Storage**: None of the nine given sources persist anything to disk, a
  database, or `UserDefaults`; `FormState.values`/`baseline` and
  `HTDVController.levels`/`selection`/`detail` are in-memory only and are
  discarded when the owning object is deallocated.
- **Transmission**: `HTDVController` transmits whatever `HTDVDataSource`'s
  `rootLevel()`/`child(for:)` implementation does internally (not among the
  given sources); `FormState.save()` transmits whatever the host's
  `FormAction.perform` closure does internally. Neither given file performs
  a network call itself.
- **Retention**: Not applicable — nothing here is retained beyond the
  lifetime of the in-memory `HTDVController`/`FormState` instance.

## Platform Notes

- **SwiftUI**: A SwiftUI host would wrap `HTDVController` and `FormState`
  in `@Observable` (or bridge their existing `onChange` callback into
  `@Published` properties on an `ObservableObject`) rather than reuse them
  unchanged, since both types are hand-rolled `@MainActor` classes with a
  single-slot callback, not `Observable`/`ObservableObject` themselves.
  Replace `HTDVLayoutEngine`'s manual width tracking with a
  `NavigationSplitView`/`HStack` chosen by a `GeometryReader`-measured
  width and the environment's `horizontalSizeClass`, but keep
  `HTDVLayoutEngine.layout(...)` itself as the pure decision function
  driving that choice. Model each `FormField` case as a `Form` row (`TextField`,
  `Toggle`, `Picker`, `TextField(value:)` with a `Formatter`, `DatePicker`,
  a custom chip-entry view for `.stringSet`) bound to `FormState.value(for:)`/`set(_:for:)`.
- **Compose**: Model `HTDVController` as a `ViewModel` exposing
  `StateFlow<HTDVUiState>` (levels/selection/detail/loading/error collapsed
  into one data class) instead of a single-slot callback, and `FormState`
  similarly as a `ViewModel` with `mutableStateOf`/`StateFlow` per field.
  Use Material 3 adaptive's `ListDetailPaneScaffold` (or a custom
  `BoxWithConstraints`-driven row of `LazyColumn`s) in place of
  `HTDVLayoutEngine`'s manual rail-count arithmetic, again keeping an
  equivalent pure `layout(...)` function as the actual decision. Map field
  kinds to `OutlinedTextField`, `Switch`, `ExposedDropdownMenuBox`,
  `OutlinedTextField` with a numeric `KeyboardType` and `visualTransformation`,
  and a `DatePickerDialog`.
- **React/Web**: Model `HTDVController` as a custom hook (e.g.
  `useHtdvController(dataSource)`) built on `useReducer`, with the
  `generation` counter held in a `useRef` so a stale async response can
  still be detected and ignored after a state update triggers a re-render;
  model `FormState` as `useReducer`-driven `values`/`baseline`/`errors`
  state with a `validate` function that mirrors `FormValidator` field-by-
  field (including anchoring a user regex with `` `^(?:${pattern})$` ``
  before calling `.test()`, and wrapping `JSON.parse` in a `try`/`catch`
  for the `.json` field kind). Use a `ResizeObserver`-driven width plus a
  media-query-style compact breakpoint in place of `isCompact`, feeding the
  same rails-vs-stack decision.
- **AppKit / UIKit**: This is the source: `Controller/HTDVController.swift`,
  `Model/HTDVModel.swift`, `Model/HTDVCellContent.swift`,
  `Layout/HTDVLayoutEngine.swift`, `Forms/FormSpec.swift`,
  `Forms/FormValue.swift`, `Forms/FormState.swift`,
  `Forms/FormValidator.swift`, and `Markdown/MarkdownEditing.swift`. The
  engine types themselves (`HTDVController`, `HTDVLayoutEngine`,
  `FormState`, `FormValidator`, `FormSpec`, `FormValue`) import only
  `Foundation` and hold no AppKit/UIKit dependency beyond the
  `PlatformViewController` type alias used as an opaque return/parameter
  type; `MarkdownEditing.swift` is the one file among the nine that also
  ships concrete AppKit (`NSTextView`/`NSViewController`) and UIKit
  (`UITextView`/`UIViewController`) implementations side by side behind
  `#if canImport(AppKit) && !targetEnvironment(macCatalyst)` /
  `#elseif canImport(UIKit)`, selected once at compile time per platform —
  see Design Decisions.
- **WinUI 3**: Model `HTDVController` as a plain C# class (or a
  `CommunityToolkit.Mvvm` `ObservableObject`) exposing `ObservableCollection<HTDVLevel>`-
  style properties and raising `INotifyPropertyChanged`/a C# `event` in
  place of the single-slot `onChange` closure; keep the `generation`-based
  stale-response guard using a plain `int` field checked after each
  `await`ed `Task<HTDVLevel>`/`Task<HTDVChild>` completes (a `CancellationToken`
  is a valid alternative for the *deeper* in-flight load `popToLevel`/
  `clearDetail` want to discard, but the source's own approach is result-
  discarding, not task-cancelling — see Design Decisions). Use a
  `NavigationView` in "left compact" mode, or a hand-built
  `Grid`/`AdaptiveTrigger`+`VisualStateManager` pair, to switch between
  side-by-side rail columns and a single-pane stack, mirroring
  `HTDVLayoutEngine.Mode`. Model `FormField` as an `abstract record`
  hierarchy (`TextField`, `ToggleField`, `SelectField`, `NumberField`,
  `DateField`, `StringSetField`, `ReadOnlyField`, `MarkdownField`,
  `JsonField`) and bind to `TextBox`, `ToggleSwitch`, `ComboBox`,
  `NumberBox`, `CalendarDatePicker`, and a `TokenizingTextBox`-style control
  for the string-set kind; validate with `System.Text.RegularExpressions.Regex`,
  anchoring a supplied pattern with `^(?:...)$` exactly as `FormValidator`
  does, and use `double.ToString("G", CultureInfo)`-based formatting (not
  `int.Parse`) for bounds messages so an out-of-`int`-range `maximum` cannot
  throw while building the message. `HTDVDataSource`'s network-backed
  implementations would use `HttpClient` and `System.Text.Json`; nothing in
  these nine sources needs `Windows.Storage`, since none of them persists
  anything (see Privacy).

## Design Decisions

**Decision**: `HTDVController` discards a stale response by comparing a
captured `generation` snapshot against the current `generation` after an
`await` resolves, rather than cancelling the underlying `Task`.
**Rationale**: The in-flight `dataSource.rootLevel()`/`child(for:)` call is
allowed to keep running to completion even after `popToLevel`, `clearDetail`,
or a newer `select`/`reload` has moved on; only the *result* is thrown away
(`stale-response-dropped`). This is simpler and safer than plumbing
`Task` cancellation through an arbitrary `HTDVDataSource` implementation
(which the doc comment says is "typically actors or `@unchecked Sendable`
classes wrapping a client" the engine does not control), at the cost of
occasionally letting a now-useless network/database call run to completion
in the background.
**Approved**: pending

**Decision**: `FormState`'s doc comment scopes it to "the save lifecycle";
it exposes no method invoking `spec.actions.delete` or `spec.actions.extra`,
and tracks no `isDeleting`/`deleteError` for them.
**Rationale**: Delete and "extra" actions are typically presented behind a
confirmation dialog (`FormDeleteAction.confirmationText`) that is
inherently a presentation-layer concern; keeping only the save lifecycle in
the engine layer means the presentation layer (`FormViewController`,
outside these given sources) owns exactly one additional, simple
responsibility — call the closure and handle its `throws` itself — instead
of duplicating `FormState`'s dirty-tracking machinery for actions that have
no "dirty" concept of their own.
**Approved**: pending

**Decision**: Both `HTDVController.fail(...)` and `FormState.save()` reduce
a thrown error to a single string via `(error as? LocalizedError)?.errorDescription
?? String(describing: error)`, discarding the original error's type and any
structured payload.
**Rationale**: `HTDVLoadError` and `FormState.saveError` are both declared
as plain strings meant to be shown directly to the user, so a uniform
reduction avoids either type having to know about every error type a given
`HTDVDataSource`/`FormAction` implementation might throw; the tradeoff is
that a non-`LocalizedError` type without a friendly `CustomStringConvertible`
description surfaces its raw Swift debug description to the user.
**Approved**: pending

**Decision**: `HTDVLayoutEngine.layout(...)` clamps its effective rail-width
divisor to a minimum of `1` even though `init(railWidth:minDetailWidth:)`
already `precondition`s `railWidth > 0`.
**Rationale**: `railWidth` is a mutable public `var`, so the init-time
precondition cannot stop a later assignment of `0` or a negative value (for
example, a caller collapsing a sidebar to width `0` for one layout pass);
clamping inside `layout` itself is what actually prevents a division-by-zero
or a trapping `Int` conversion at the point the value is used, rather than
only at construction.
**Approved**: pending

**Decision**: `MarkdownEditing.swift` defines the `MarkdownEditing` protocol
and ships a concrete default implementation (`PlainTextMarkdownEditing`,
with AppKit and UIKit view controllers) in the same file, unlike the other
eight given sources, which hold no AppKit/UIKit-specific code.
**Rationale**: Per the source's own comment, `PlainTextMarkdownEditing` is
explicitly a placeholder — "adequate for configuration notes until the
markdown module lands" — with the hub app expected to inject a real
implementation through `HubModules.markdownEditing`; bundling a working
default alongside the protocol lets every consumer of the Forms subsystem's
`.markdown` field render *something* today without depending on that
richer, not-yet-given module.
**Approved**: pending
