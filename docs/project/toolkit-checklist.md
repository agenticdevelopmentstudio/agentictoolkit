# Toolkit Checklist

A checklist to review against when writing or reviewing toolkit code. Invoke this explicitly — I'll walk each section and flag anything that doesn't meet the bar.

---

## 1. Principles

- [ ] **App-agnostic.** Toolkit code does not name, reference, or assume any specific app. No `"AgenticPluginTester"` strings, no `Bundle.main.bundleIdentifier` assumptions beyond what clients opt into.
- [ ] **Reusable across apps.** The code solves a problem more than one app would have. If it's only ever useful for one app, it stays in the app.
- [ ] **Decouple before moving.** Before lifting something into the toolkit, introduce a value type or protocol at the boundary so the toolkit doesn't absorb app-specific dependencies (e.g. `WindowActivationTarget` instead of a concrete `Session` struct; `ChatBackend` instead of `PluginManager`).
- [ ] **Layering respected.** Toolkit targets must not depend on client code. Dependencies point inward only: `Core` ← `Scripting`/`AIProvider` ← `CoreUI` ← feature targets (`LoggingWindow`, `ChatWindow`, `NotesWindow`, `SettingsWindow`, `TerminalWindow`, `FileBrowser`).
- [ ] **Minimal, intentional public surface.** Every `public` symbol is a commitment. Start `internal` and promote deliberately.
- [ ] **Testable in isolation.** Hard dependencies (screens, filesystem, keychain, network) are abstracted behind protocols with injectable alternatives.

## 2. Swift Code

- [ ] **Swift 6 language mode.** Source code compiles clean under Swift 6 strict concurrency. No `-swift-version 5` escape hatches.
- [ ] **Concurrency isolation is explicit.** `@MainActor` on UI types and anything that must touch AppKit. `Sendable` on value types crossing actor boundaries.
- [ ] **No `Task.detached` capturing `self` unsafely.** Prefer structured `Task { ... }` with inherited actor context.
- [ ] **Values over references.** Prefer `struct` and `enum`. Use `class` only when identity, reference semantics, or `@MainActor` state is genuinely needed.
- [ ] **Visibility matches intent.** Public types have public inits and public members for everything external callers need. Don't ship a `public` type with no `public init`.
- [ ] **Doc comments on public API.** `///` on every public type, method, and non-obvious parameter. State what, not how.
- [ ] **No forced casts, forced unwraps, or `fatalError` on happy paths.** Reserve `!` for programmer-enforced invariants with a note.
- [ ] **No silent failure.** If an operation can fail, it throws or returns an error; it does not swallow and return a default.
- [ ] **Deprecated API avoided.** No warnings about deprecated NSTableView styles, etc.

## 3. Agentic-Toolkit Code

- [ ] **Lives in the right module.** `Core` for Foundation-only cross-platform utilities; `CoreUI` for cross-cutting AppKit UI (windowing, shared views); a feature target (`LoggingWindow`, `ChatWindow`, etc.) for standalone features; `Scripting`/`AIProvider` for Foundation-only services.
- [ ] **No app-specific strings or identifiers.** Logger subsystems use toolkit-owned namespaces (`"CoreUI"`, `"TerminalWindow"`, not `"com.mikefullerton.AgenticPluginTester"`). File paths are parameterized, not hardcoded.
- [ ] **Dependency injection for I/O.** Screens, storage, clocks, loggers, network — all injectable. Defaults are convenience, not requirements.
- [ ] **Protocols define behaviors clients implement.** If the toolkit needs data from the client, it asks via a protocol (e.g. `ScreenProvider`, `ChatBackend`, `SettingsTopic`, `AISettingsPersistence`).
- [ ] **Value types for data crossing the boundary.** Clients pass in plain structs (`WindowActivationTarget`, `ChatBackendMessage`, `WindowSpec`) — not their domain objects.
- [ ] **Generic over client types where appropriate.** `SettingsView<Topic>`, `SettingsWindowController<Topic>` — let clients bring their own type without casting.
- [ ] **Documentation comments include usage examples** for anything non-obvious (registration flow, window lifecycle, stream lifetimes).
- [ ] **Tests exist.** Public types have at least smoke tests colocated under their feature's `Tests/` subdirectory in `agentictoolkit/packages/apple/AgenticToolkit/`. Pure-math and value types get unit tests; UI types get construction tests.
- [ ] **Builds clean via `xcodebuild` on the `AgenticToolkitMacOS` scheme** (see `.claude/CLAUDE.md` for the full command). No errors, no new warnings.

## 4. Client Code

- [ ] **Imports only what it uses.** `import CoreUI` / `import LoggingWindow` / etc. only in files that touch those toolkit types.
- [ ] **Implements toolkit protocols, doesn't fork them.** If a toolkit protocol doesn't fit, discuss extending the toolkit — don't work around it by copying code.
- [ ] **Translates at the boundary.** App domain types (e.g. `Session`) are mapped to toolkit value types (e.g. `WindowActivationTarget`) at the call site. The toolkit never sees app types.
- [ ] **Respects toolkit actor isolation.** If a toolkit type is `@MainActor`, the caller lives on the main actor or hops with `Task { @MainActor in ... }`.
- [ ] **Doesn't reach into toolkit internals.** No `@testable import` in production code. No assumptions about private state.
- [ ] **No duplicated toolkit functionality.** If the app has its own `WindowManager`, `SettingsView`, or `Logger` wrapper, check whether the toolkit already provides one before keeping the local copy.
- [ ] **Submodule/dependency pinned appropriately.** The app pulls in a specific toolkit commit or tag; bumping it is a deliberate, reviewable change.
