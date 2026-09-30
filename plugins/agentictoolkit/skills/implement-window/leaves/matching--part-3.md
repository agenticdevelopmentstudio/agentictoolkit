<!-- leaf: implement-window/matching--part-3 · source: window-matching.md -->

# Window Matching — continued (part 3)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `SystemWindowMatcher.init(registry:)` | `HeuristicRegistry` | `HeuristicRegistry.shared` | Heuristic lookup used for fingerprinting and live-pattern extraction |
| `matchWindows(threshold:)` | `Int` | `autoAssignThreshold` (80) | Minimum score for a pair to be matched |
| `SystemWindowMatcher.autoAssignThreshold` | `Int` (static let) | 80 | Default auto-assign threshold |
| `SystemWindowMatcher.minSubstringPatternLength` | `Int` (static let) | 2 | Minimum stored-pattern length for a 60-point containment match |
| `HeuristicRegistry.init(heuristics:)` | `[AppHeuristic]?` | nil (the five built-ins) | Initial heuristics |
| `HeuristicRegistry.registerCustomRules(_:)` | `[CustomHeuristicRule]` | none registered | User rules layered over the initial heuristics |
| `CustomHeuristicStore.init(rootDirectory:)` | `URL` | required | Directory holding `heuristics.json` (the toolkit's manager passes its state store's root) |
| `CustomHeuristicRule.matchMode` | `CustomMatchMode` | `.substring` | How `titlePattern` is interpreted |
| `CustomHeuristicRule.autoAssign` | `Bool` | false | Auto-assign flag, read by the context manager (see rule-auto-assign) |
| `CustomHeuristicRule.targetContextName` | `String?` | nil | Auto-assign target context name (see rule-auto-assign) |
| `CustomHeuristicRule.name` | `String` | `"<appName> - <titlePattern>"` | Display name |

No environment variables or settings keys are read.

## Localization

The component contains user-facing English literals with no localization:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | Substring | `CustomMatchMode.displayName` for `.substring` |
| (none — hardcoded) | Regex | `CustomMatchMode.displayName` for `.regex` |
| (none — hardcoded) | `<appName> - <titlePattern>` | Default `CustomHeuristicRule.name`, shown in Settings |

The built-in heuristic `name` values (for example "Terminal") are also hardcoded. Log messages are developer-facing and not localized.

## Privacy

- **Data collected**: window owner names and titles are read in memory from the `SystemWindowInfo` values the caller passes; titles can contain document names, page titles and hostnames.
- **Storage**: only user-authored `CustomHeuristicRule` values are persisted, as plain JSON in `rootDirectory/heuristics.json`; fingerprints are persisted by the caller's context store, not by this component.
- **Transmission**: nothing leaves the device.
- **Retention**: `heuristics.json` persists until overwritten by `saveRules` or deleted by `removeAll`.
- **Logs**: invalid-regex errors log the pattern with `privacy: .public`; the window title is not logged.

## Platform Notes

- **SwiftUI**: No view code; the source is plain Swift in `Core/SystemWindows/Matching/` built on Foundation (`NSRegularExpression`, `JSONEncoder`/`JSONDecoder`, `FileManager`, `NSLock`) and `os.Logger` via `Loggable`. `AppHeuristic.swift` holds the protocol and `HeuristicTitleParser`; `CustomHeuristicRule.swift` the rule and `CustomMatchMode`; `CustomHeuristic.swift` the adapter; `CustomHeuristicStore.swift` the JSON store; `HeuristicRegistry.swift` the locked registry; `SystemWindowMatcher.swift` fingerprinting, scoring and greedy assignment. A SwiftUI host drives it from an `@MainActor` model, as `SystemWindowContextManager` does. Swift's `Regex` could replace `NSRegularExpression`, but the case-insensitive flag, the non-empty-match rule and UTF-16 range mapping must be preserved.
- **Compose**: Port to plain Kotlin: an `interface AppHeuristic` with default methods, `data class` rule with `kotlinx.serialization` (ISO 8601 via `Instant`), `java.util.regex.Pattern` with `CASE_INSENSITIVE` (add `UNICODE_CASE` to approximate Foundation), a `ReentrantLock` or `synchronized` registry, and `Files.move(..., ATOMIC_MOVE)` for the atomic save. `String.lowercase()` matches Swift's `lowercased()`; use `contains(ignoreCase = true)` for the locale-aware rule comparison. Use `sortedWith(compareByDescending { score }.thenBy { contextId.toString() }...)`; Kotlin's sort is stable, but keep the explicit tie-breakers for parity.
- **React/Web**: TypeScript: `interface AppHeuristic`, a `Map<string, AppHeuristic>` keyed by `toLowerCase()`, `new RegExp(pattern, "i")` (JS regex syntax differs from ICU; `\d`, groups and anchors port, possessive quantifiers and some Unicode classes do not), and `JSON.stringify` with a key-sorting replacer. The registry needs no lock in single-threaded JS. Persistence goes to `localStorage`/IndexedDB or a Node `fs.writeFile` to a temp file then `rename`. `Array.prototype.sort` is stable, but keep the four-key comparator. Compare UUIDs by their uppercase string form to match `uuidString` ordering.
- **AppKit / UIKit**: The same Core sources compile unchanged for AppKit hosts; window data comes from `CGWindowListCopyWindowInfo` (owner name, title, display). UIKit has no cross-app window list, so on iOS only the rule, store and registry types are meaningful, and there are no live windows to match.
- **WinUI 3**: Port to .NET in a class library with no XAML. `AppHeuristic` becomes an `interface IAppHeuristic` with default interface methods for `RecommendedStrategy` and `FingerprintPattern` (returning a `(string Pattern, MatchStrategy Strategy)?` tuple). `CustomHeuristicRule` becomes a `record` serialized with `System.Text.Json` (`JsonSerializerOptions { WriteIndented = true }`, `JsonStringEnumConverter` with camelCase so `"substring"`/`"regex"` round-trip; ISO 8601 `DateTimeOffset` is the default). Sorted keys are not built in, so either order properties with `[JsonPropertyOrder]` alphabetically or accept a different on-disk order. `CustomHeuristicStore` uses `Windows.Storage.ApplicationData.Current.LocalFolder` (packaged) or a caller-given `DirectoryInfo`, `Directory.CreateDirectory`, and an atomic save via write-to-temp then `File.Replace`/`File.Move(overwrite: true)`; its methods may become `Task`-returning `async` with `StorageFile` APIs, which changes the synchronous contract. `HeuristicRegistry` uses a `Dictionary<string, IAppHeuristic>(StringComparer.OrdinalIgnoreCase)` guarded by `lock` (or `ReaderWriterLockSlim`); note `OrdinalIgnoreCase` differs slightly from Swift `lowercased()` for some non-ASCII characters. Regex uses `System.Text.RegularExpressions.Regex` with `RegexOptions.IgnoreCase | RegexOptions.CultureInvariant` and a `Match.Length > 0` check; cache compiled regexes if desired, since .NET has no equivalent of the per-call log. Window data comes from `EnumWindows`/`GetWindowText`/`GetWindowThreadProcessId` plus `MonitorFromWindow` for `display`, with the process name as `app`. If the rule list is bound to a Settings page, expose it as an `ObservableCollection<CustomHeuristicRule>` and raise `INotifyPropertyChanged` on the view model, calling `RegisterCustomRules` after each change. Sort candidates with `OrderByDescending(c => c.Score).ThenBy(c => c.ContextId.ToString("D").ToUpperInvariant(), StringComparer.Ordinal)...`.

