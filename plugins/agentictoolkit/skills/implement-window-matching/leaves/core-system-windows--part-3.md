<!-- leaf: implement-window-matching/core-system-windows--part-3 · source: window-matching-core-system-windows.md -->

# Window Matching Core System Windows — continued (part 3)

## Platform Notes

- **SwiftUI**: No SwiftUI code in the source. A SwiftUI host keeps an array of `SystemWindowContext` in an `@Observable` model and drives a strategy `Picker` from `MatchStrategy.allCases` with `displayName` labels; mutations go through the same `mutating` methods on the model's stored copy.
- **Compose**: Port each struct to a Kotlin `data class` (immutable `val` for the Swift `let` fields; `copy(...)` stands in for both `withTitle` and `mutating` updates) and `MatchStrategy` to an `enum class` with a `displayName` property sourced from `strings.xml`. Use `kotlinx.serialization` with `@Serializable`, `java.util.UUID` or a `String` ID, `kotlinx.datetime.Instant` for dates, and a small `@Serializable` rect class encoded as `[[x,y],[w,h]]` to stay wire-compatible. Android has no API to enumerate other apps' windows, so `SystemWindowInfo` is only meaningful as a data model there.
- **React/Web**: Model the enum as a string-literal union `'appAndTitleExact' | 'appAndTitleSubstring' | 'appAndTitleRegex' | 'appOnly'` and the structs as readonly TypeScript interfaces, with context operations as pure functions returning a new context (for example `addWindow(ctx, snap): SystemWindowContext`) so the "first match by id, replace in place" rule is explicit. Use `crypto.randomUUID()` for IDs, ISO strings for dates, and validate on `JSON.parse` with a schema library (for example zod) to reproduce missing-key-throws and strategy-unknown-raw. Browsers cannot list OS windows.
- **AppKit / UIKit**: This is the source, in `packages/apple/AgenticToolkit/Core/SystemWindows/`: `MatchStrategy.swift`, `SystemWindowFingerprint.swift`, `SystemWindowInfo.swift`, `SystemWindowSnapshot.swift` and `SystemWindowContext.swift`. They import only Foundation and CoreGraphics (for `CGRect`) and build for macOS and iOS; the CGWindowID and display ID values come from macOS `CGWindowListCopyWindowInfo` and `CGDirectDisplayID` in the macOS-only consumers, so on iOS the types are data models only.
- **WinUI 3**: Port each struct to a C# `record` (or `readonly record struct` for `SystemWindowFingerprint` and `SystemWindowInfo`) with `init`-only properties for the Swift `let` fields; `withTitle` becomes a `with { Title = newTitle }` expression. Map `id: UInt32` to the window's `HWND` (store as `long`/`nint` from `EnumWindows`), `app` to the process name from `Process.GetProcessById(pid)`, `title` to `GetWindowText`, `frame` to `GetWindowRect` as a `Windows.Foundation.Rect` or `RECT`, `display` to the `HMONITOR` from `MonitorFromWindow`, and `isOnScreen` to `IsWindowVisible` plus not `IsIconic`; Windows windows have no layer number, so `layer` needs a stand-in (Z-order index or `WS_EX_TOPMOST`). `MatchStrategy` becomes a C# `enum` serialized with `JsonStringEnumConverter` so names match the Swift raw values, and `displayName` moves to `.resw` resources through `ResourceLoader`. Serialize with `System.Text.Json`, setting `JsonIgnoreCondition.WhenWritingNull` to match optional-omitted and `required` members or `JsonRequired` to match missing-key-throws; write a custom `JsonConverter<Rect>` for the `[[x,y],[w,h]]` form. `SystemWindowContext` holds its snapshots in a `List<T>` (or `ObservableCollection<T>` when bound to UI) and becomes a class raising `INotifyPropertyChanged`; that is a reference type, so copy it explicitly where Swift relies on value semantics, and marshal edits to the UI thread through `DispatcherQueue` instead of relying on `Sendable`. Store files under `Windows.Storage.ApplicationData.Current.LocalFolder` in a packaged app, or under `%LOCALAPPDATA%` when unpackaged.

## Design Decisions

**Decision**: A snapshot's stable `id` is a `UUID` separate from the CGWindowID, and the CGWindowID is optional.
**Rationale**: Per the `SystemWindowSnapshot` doc comment, the CGWindowID "may become stale after restart"; a separate stable ID lets a context keep a dormant snapshot and re-attach a new live window to it through the fingerprint.
**Approved**: pending

**Decision**: `SystemWindowFingerprint.titlePattern` holds regex source, not a captured value, for `appAndTitleRegex`.
**Rationale**: Per the `MatchStrategy.appAndTitleRegex` doc comment, storing the source means "every title in the same family re-matches after restart" (for example every `JIRA-<n>` window).
**Approved**: pending

**Decision**: The snapshot stores `display` and `app` beside the fingerprint's own copies.
**Rationale**: `display` is the restore target and changes when the user moves the window, while `fingerprint.display` records where it was first seen for tie-breaking; `app` is duplicated for direct access and nothing enforces equality.
**Approved**: pending

**Decision**: `SystemWindowContext` does not enforce unique `windowID`s or a valid `lastFocusedWindowID`.
**Rationale**: The value type stays a plain container; cross-context rules (a window in at most one context) need the whole context list, so `SystemWindowContextManager` enforces them.
**Approved**: pending

**Decision**: `MatchStrategy.displayName` lives on the model and returns English literals.
**Rationale**: The doc comment keeps it beside the enum, like `CustomMatchMode.displayName`, so hosts read labels without reaching into the macOS UI layer; the strings are not externalized, which is recorded as a failed check under Compliance.
**Approved**: pending

**Decision**: The types rely on synthesized `Codable` with no versioning.
**Rationale**: Synthesis keeps the wire format equal to the Swift property names; the cost is that a missing key or unknown strategy fails the whole decode, which the store reports as a decode error.
**Approved**: pending
