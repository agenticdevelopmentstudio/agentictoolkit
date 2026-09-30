<!-- leaf: implement-general-1/markdown-core--part-3 · source: markdown-core.md -->

# MarkdownCore — continued (part 3)

## Platform Notes

- **SwiftUI**: Not a view; a SwiftUI screen observes this store through an observable wrapper around `MarkdownStore`, never by subclassing it or reaching into the underlying database directly.
- **Compose**: The Kotlin equivalent would pair a Room- or SQLDelight-backed store with the same schema shape, exposed to Compose through a view-model and observable state, not observed directly.
- **React/Web**: The web equivalent has no local SQLite; the nearest analog is an IndexedDB-backed store with the same pull-only/outbox split, exposed to React through a hook, not a component prop.
- **AppKit / UIKit**: Same as SwiftUI — this store is UI-framework-agnostic; an AppKit or UIKit controller would hold a reference and observe it through the same wrapper any other consumer uses, never a delegate protocol specific to this component.
- **WinUI 3**: A Windows port would replace the GRDB-backed database with a `Microsoft.Data.Sqlite`-backed store, replace `MarkdownRemoteWriter.send` with `HttpClient` calls encoding payloads through `System.Text.Json`, replace the per-token home directory with a folder under `Windows.Storage.ApplicationData`, run the drain as a `Task`, and expose document lists to XAML through an `ObservableCollection` with `INotifyPropertyChanged` rather than this store's plain array return values.

## Design Decisions

**Decision**: Keep the revive-on-conflict update's guard clause — reviving only a row whose delete column is set — so that re-adding an edge, assignment, or keyword that is already live changes no columns, rather than letting the upsert unconditionally rewrite the updated-at and ordering columns on every call.
**Rationale**: An unconditional update would stage a mutation into the taxonomy outbox on every idempotent re-add, since staging follows the count of rows the database engine reports as actually changed; the guard makes "already exists and live" distinguishable from "actually changed" at the SQL level instead of requiring a pre-read.
**Approved**: pending
