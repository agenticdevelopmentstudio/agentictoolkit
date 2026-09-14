// `PermissionWalkthrough` moved down into AgenticToolkitPermissionsUI so an
// app can run the walkthrough without linking this framework's heavy
// dependency set. Consumers that reach it through `import AgenticToolkitMacOS`
// keep working unchanged.
//
// `PermissionsSettingsPanelViewController` stayed behind, in this directory:
// it is a `ComposableSettings.SettingsPanelViewController` subclass, and
// ComposableSettings lives in *this* framework
// (`macOS/SystemIntegration/ComposableSettingsWindow/`). Moving the panel down
// would point PermissionsUI upward at the tier it is trying to escape. Hosts
// that do not have a ComposableSettings window — the ones this split exists
// for — want `PermissionsPanelView` or `PermissionWalkthrough` directly
// anyway; the panel is the wrapper that adapts them to a settings window.
@_exported import AgenticToolkitPermissionsUI
