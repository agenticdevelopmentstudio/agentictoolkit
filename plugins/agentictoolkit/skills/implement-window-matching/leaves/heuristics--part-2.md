<!-- leaf: implement-window-matching/heuristics--part-2 · source: window-matching-heuristics.md -->

# Window Matching Heuristics — continued (part 2)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` (argument to `extractPattern(from:)` / `fingerprintPattern(for:)`) | `String` | — (required) | The raw window title supplied by the caller (the window list's title for the window). |
| `HeuristicTitleParser.separators` | `[String]` (static `let`) | `[" — ", " – "]` | Title separators, most specific first; a constant, not caller-configurable. |
| `recommendedStrategy` | `MatchStrategy` | `.appAndTitleSubstring` (`TerminalHeuristic`: `.appOnly`) | Strategy stored in fingerprints produced by each heuristic; fixed per type. |
| `appNames` | `[String]` | per heuristic (see identity requirements) | Owning-app names the registry maps to the heuristic; fixed per type. |

The heuristics take no initializer parameters (`init()` only), read no
environment variables or settings keys, and have no injected dependencies.

## Localization

The heuristics produce no user-facing messages. Each `name` is a hardcoded
English (or product-name) literal documented as "the user-visible name for
this heuristic", with no localization lookup:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (literal, `XcodeHeuristic.name`) | Xcode | Heuristic display name |
| (literal, `WarpHeuristic.name`) | Warp | Heuristic display name |
| (literal, `BraveHeuristic.name`) | Brave Browser | Heuristic display name |
| (literal, `VSCodeHeuristic.name`) | VS Code | Heuristic display name |
| (literal, `TerminalHeuristic.name`) | Terminal | Heuristic display name |

The parsing literals (" - Brave", the VS Code generic titles "Visual Studio
Code", "Welcome", "Get Started", "Settings") match English application
titles only; a localized VS Code or Brave title is not recognized and falls
through to the default branch.

## Platform Notes

- **SwiftUI**: Source platform (the logic is Foundation-only and has no SwiftUI dependency). Files: `Core/SystemWindows/Matching/AppHeuristic.swift` (protocol, default `recommendedStrategy`/`fingerprintPattern(for:)`, `HeuristicTitleParser`), `Matching/Heuristics/XcodeHeuristic.swift`, `WarpHeuristic.swift`, `BraveHeuristic.swift`, `VSCodeHeuristic.swift`, `TerminalHeuristic.swift`, and `Core/SystemWindows/MatchStrategy.swift`. Swift specifics a port must reproduce: `String.components(separatedBy:)` keeps empty pieces while `split(separator:)` drops them (VS Code's filename test and Warp's path split rely on the dropping form); `trimmingCharacters(in: .whitespaces)` excludes newlines; `hasSuffix`/`range(of:)` are literal, case-sensitive matches; `dropLast(n)` counts `Character`s. A SwiftUI host would show `name` in a picker and read `MatchStrategy.displayName` for the strategy label.
- **Compose**: Port to plain Kotlin — an `interface AppHeuristic` with default methods for `recommendedStrategy` and `fingerprintPattern`, `object`/`data object` implementations, and a `Pair<String, MatchStrategy>?` (or small data class) for the fingerprint result. Use `String.split(" — ")` (keeps empty pieces, like `components(separatedBy:)`) for the separator, and `split('.').filter { it.isNotEmpty() }` for the filename test. Kotlin's `trim()` strips all whitespace including newlines; use `trim { it == ' ' || it == '\t' }` to match `.whitespaces`. `endsWith`/`startsWith` are case-sensitive by default, matching the source. Stateless objects are thread-safe, matching `Sendable`.
- **React/Web**: Port to TypeScript — an `AppHeuristic` interface plus a helper providing the default strategy (`'appAndTitleSubstring'`) and fingerprint derivation, returning `string | null` / `{ pattern, strategy } | null`. `String.prototype.split(' — ')` keeps empty pieces; filter empties for the filename and Warp path cases. `trim()` also strips newlines, so use a replace against a space/tab-only class to match `.whitespaces`. `endsWith`/`indexOf(' (')` reproduce `hasSuffix`/`range(of:)`. JS strings index UTF-16 code units, while Swift `dropLast` counts grapheme clusters; the suffixes involved (" - Brave", " *", "-") are ASCII, so results are identical.
- **AppKit / UIKit**: Same as the source; the heuristics are Foundation-only and run unchanged in an AppKit or UIKit host. On macOS the `title` comes from the window list's window name and `appNames` are compared with the owning-app name (`CGWindowListCopyWindowInfo`'s owner name, per the `AppHeuristic` doc comment); UIKit has no equivalent system-wide window list, so on iOS the heuristics apply only to titles supplied by the app itself.
- **WinUI 3**: Port to C# in a .NET class library — `public interface IAppHeuristic` with C# 8 default interface members for `RecommendedStrategy` (returning `MatchStrategy.AppAndTitleSubstring`) and `FingerprintPattern(string title)` returning `(string Pattern, MatchStrategy Strategy)?`; implement each heuristic as a `sealed record` or stateless `sealed class` (immutable, therefore thread-safe like `Sendable`, and callable from any `Task`). Use `title.Split(" — ", StringSplitOptions.None)` to keep empty components like `components(separatedBy:)`, and `Split('.', StringSplitOptions.RemoveEmptyEntries)` for the filename test and Warp's path split. `string.Trim()` strips all whitespace including newlines; use `Trim(' ', '\t')` to match `.whitespaces`. Use `EndsWith(" - Brave", StringComparison.Ordinal)`, `StartsWith("-", StringComparison.Ordinal)`, and `IndexOf(" (", StringComparison.Ordinal)` — the default culture-sensitive overloads differ from Swift's literal matching; a `HashSet<string>` with `StringComparer.Ordinal` holds the generic titles, and `StringComparer.OrdinalIgnoreCase` (or `ToLowerInvariant()`) holds the extension set. The title formats themselves are macOS-specific: on Windows the window title comes from `GetWindowText` (Win32) or the Windows App SDK `AppWindow.Title`, the owner is a process name such as "Code.exe" or "WindowsTerminal.exe", and title shapes differ (VS Code on Windows uses " - " rather than an em dash, Brave appends " - Brave" the same way), so `AppNames` and separators need Windows-specific values while the parsing rules port unchanged. `MatchStrategy` maps to a C# `enum` serialized by name with `System.Text.Json`'s `JsonStringEnumConverter` to keep the source's `String` raw values.

## Design Decisions

**Decision**: A heuristic returns `nil` rather than an empty string or an error when it cannot extract a pattern.
**Rationale**: `SystemWindowMatcher` treats `nil` as "fall back to the raw title with the substring strategy" (or app-only for an empty title); a single optional result keeps the heuristics pure and leaves the fallback policy in one place.
**Approved**: pending

**Decision**: `HeuristicTitleParser` splits on the en dash as well as the em dash, accepting that content containing " – " gets split.
**Rationale**: The parser's NOTE states em dash is by far the common separator, a few locales/builds use an en dash, and content en-dashes are rare; the behavior is covered by `HeuristicTests` (the Xcode en-dash test).
**Approved**: pending

**Decision**: `TerminalHeuristic` recommends `appOnly` for every title, not only for plain shells.
**Rationale**: The doc comment states plain-shell titles are not distinctive enough and appOnly "is the safest default"; the code applies it unconditionally, so even a distinctive command such as "ssh user@host" is fingerprinted app-only while the extracted command is still stored as the pattern.
**Approved**: pending

**Decision**: `WarpHeuristic` returns `nil` for a root path instead of "/".
**Rationale**: The code comment and the `warpRoot` test state a bare root yields no useful pattern; returning "/" would substring-match every path-bearing Warp title.
**Approved**: pending

**Decision**: `VSCodeHeuristic` prefers the last component only when the first looks like a filename and the last does not, using a fixed list of 27 common extensions.
**Rationale**: VS Code puts the workspace first when one is open but shows "file — workspace" in other layouts; the fixed list avoids treating dotted project names (for example "v1.2") as filenames.
**Approved**: pending

**Decision**: Only `WarpHeuristic` parses an ASCII " - " and has no whole-title fallback; Brave parses the " - Brave" suffix; the rest use `HeuristicTitleParser`.
**Rationale**: Warp and Brave titles use a hyphen, not a dash separator; Warp without " - " is not in its "user - directory" format, so the heuristic declines rather than guessing.
**Approved**: pending
