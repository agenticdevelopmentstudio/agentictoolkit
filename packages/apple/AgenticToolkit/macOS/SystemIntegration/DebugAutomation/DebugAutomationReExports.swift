// `QuietWindowPresentation`, `DebugLaunchSwitch`,
// `NSApplication.activateUnlessQuiet()` and the `NSWindow` quiet-presentation
// helpers moved down into AgenticToolkitCoreMacOS (`CoreMacOS/DebugAutomation/`).
//
// Why: `PermissionWalkthrough` now lives in AgenticToolkitPermissionsUI, and it
// activates the app before running its modal alert. `activateUnlessQuiet()` is
// the single place that knows when *not* to take the foreground — under XCTest
// and under an automated Debug session — and a walkthrough that reached for
// `activate(ignoringOtherApps:)` instead would be exactly the focus-stealing
// bug that helper was written to remove. The quiet-presentation switch is
// AppKit and Foundation only, so CoreMacOS is the lowest tier that can hold it,
// and dependencies point downward.
//
// Re-exported here because hosts reach these through `import
// AgenticToolkitMacOS` without importing AgenticToolkitCoreMacOS themselves.
@_exported import AgenticToolkitCoreMacOS
