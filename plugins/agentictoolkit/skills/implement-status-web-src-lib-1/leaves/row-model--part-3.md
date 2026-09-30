<!-- leaf: implement-status-web-src-lib-1/row-model--part-3 · source: status-web-src-lib-row-model.md -->

# Status Row Model — continued (part 3)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `nowMs` (`rowToStatusRowProps`, `rowToText`, `rowsToText`, `deployDtoUnconfirmed`) | `number` | none (required) | Epoch milliseconds used for relative time labels and the demotion clock; injected so the functions stay pure. |
| `probeIntervalMs` (`unconfirmedWindowMs`, `deployDtoUnconfirmed`) | `number` or undefined | undefined, treated as 0 | The backend probe cadence (from `Board.probeIntervalMs`); the window is five times it, floored at 10 minutes. |
| `UNCONFIRMED_AFTER_MS` | constant `number` | `600000` | Floor of the unconfirmed window. |

There are no environment variables, settings keys or injected services.

## Localization

The module holds hardcoded English strings with no localization layer:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `STATE_LABEL.down` | `down` | Problem status word |
| `STATE_LABEL.degraded` | `degraded` | Problem status word |
| `STATE_LABEL.failed` | `deploy failed` | Problem status word |
| `STATE_LABEL.stuck` | `deploy stuck` | Problem status word |
| `STATE_LABEL.stale` | `deployment failed` | Problem status word for a production deploy behind newer unpromoted builds |
| `STATE_LABEL.unreachable` | `platform unreachable` | Problem status word when a provider API cannot be polled |
| `STATE_LABEL.erroring` | `app errors` | Problem status word when the app throws while its host answers |

Activity status words arrive already spelled by the server (`ActivityRow.verb`). Time labels (`just now`, `m`, `h`, `d`), environment badges and source labels come from `time-ago.ts`, `colors.ts` and `issue-sources.ts`, also English-only.

## Platform Notes

- **SwiftUI**: Model `Row` as a `struct Row: Sendable, Hashable, Identifiable` (id = `key`) and `RowTone` as a `String`-backed `enum`; builders become `init(problem:)` and `init(activity:)`. Map tones to `Color` assets rather than CSS variables, and bold via `.fontWeight(.bold)` when tone is `.bad`. Use `RelativeDateTimeFormatter` only if you accept its different wording; to match `timeAgo` port the four thresholds by hand. Parse ISO dates with `ISO8601DateFormatter` (enable fractional seconds) and treat a nil parse as the fail-closed path. Clipboard: `UIPasteboard.general.string` or `NSPasteboard`.
- **Compose**: A Kotlin `data class Row` and `enum class RowTone`; builders as extension functions `Problem.toRow()`. Tone colors map to `MaterialTheme` or app color tokens. `Instant.parse` throws on bad input, unlike `Date.parse`'s `NaN`, so catch `DateTimeParseException` and return `true` to keep dto-fail-closed. Clipboard via `ClipboardManager.setText(AnnotatedString(...))`.
- **React/Web**: The source is `packages/web/packages/status-web/src/lib/row-model.ts`, tested by `row-model.test.ts` (Vitest). `rowToStatusRowProps` feeds `components/StatusRow.tsx`; `ActivityPanel.tsx` uses `rowSearchText` and `rowsToText` (through `CopyButton`); `DeployList.tsx` and `deploy-view.ts` call `deployDtoUnconfirmed`. Tone colors are CSS custom properties (`--color-apt-*`) resolved by the theme.
- **AppKit / UIKit**: Same Swift model as SwiftUI; tone colors become `NSColor`/`UIColor` named assets, and the adapter output drives an `NSTableCellView` or `UICollectionViewListCell` content configuration. Clipboard via `NSPasteboard.general.setString(_:forType: .string)` or `UIPasteboard.general.string`.
- **WinUI 3**: Put `Row` in a shared .NET class library as a `sealed record Row` with a `RowTone` enum, and `ProblemToRow`/`ActivityToRow` as static factory methods over DTOs deserialized with `System.Text.Json` (use `JsonStringEnumConverter` with camel-case naming for `tone`). The `StatusRowProps` adapter becomes a view-model type implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm `ObservableObject`), exposing `StatusBrush` as a `SolidColorBrush` looked up from `Application.Current.Resources` theme resources (for example `SystemFillColorSuccessBrush`, `SystemFillColorCriticalBrush`, `SystemFillColorCautionBrush`, `TextFillColorSecondaryBrush`) and `StatusWeight` as `FontWeights.Bold` or `FontWeights.Normal`; bind a `ListView` to an `ObservableCollection<RowViewModel>`. Parse timestamps with `DateTimeOffset.TryParse(..., CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)` and return `true` on failure to keep dto-fail-closed. `rowsToText` maps to `string.Join("\n", rows.Select(RowToText))`; write it with `DataPackage.SetText` and `Clipboard.SetContent`. Pass `nowMs` as a `DateTimeOffset` or inject `TimeProvider` so the functions stay testable. Keep `STATE_LABEL` in a `.resw` file if localizing, which the source does not do.

## Design Decisions

**Decision**: One `Row` shape and one adapter serve every pane.
**Rationale**: The header comment: every pane gets "identical row capabilities (clickable commits, consistent links) and a new field is added in one place".
**Approved**: pending

**Decision**: The builders make no judgments; the server's state, verb and tone are rendered verbatim.
**Rationale**: "The server has already decided what is a problem, what happened, and when — these builders only spell the row." A removed client-side `displayStatus` step that demoted aged rows to "last seen building" was unreachable and could only disagree with the server's own expiry (`rowToStatusRowProps` doc comment and the C3 regression tests).
**Approved**: pending

**Decision**: The only client freshness clock judges raw `DeploymentDTO`s, scaled to five times the probe interval with a 10-minute floor, and fails closed.
**Rationale**: The panels that render DTOs directly are "the last place the client still holds a phase the server has not already ruled on"; scaling mirrors `snapshotStaleMs` so a slower poller does not false-demote, and an unreadable date must not assert live progress.
**Approved**: pending

**Decision**: A commit sha is shown only when it links to GitHub.
**Rationale**: "a bare, non-clickable hash is noise"; the subject still shows on its own.
**Approved**: pending

**Decision**: Activity rows take their platform from `ActivityRow.source`, falling back to `kind`.
**Rationale**: The server stamps the raw provider spelling (`cloudflare-pages`, not the canonical `cloudflare` in the target), so no parsing is needed, and the fallback keeps the clipboard and source columns non-empty.
**Approved**: pending

**Decision**: Clipboard text is one tab-separated line per row with a fixed seven columns and friendly labels.
**Rationale**: Copied panes paste as aligned spreadsheet columns and "copied text matches the screen"; the unescaped-field gap is the open question on text-field-escaping.
**Approved**: pending

**Decision**: `problemToRow` sets `downSince` to `since` for every problem.
**Rationale**: The source does this unconditionally; `row-detail.ts` reads `downSince ?? at`, and both hold the same value on problem rows, so the display is unaffected even though the field's doc comment describes it as endpoint-specific.
**Approved**: pending
