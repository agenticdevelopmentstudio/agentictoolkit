import Foundation

/// UUIDs from the Universal Control spike's Fixture map
/// (docs/superpowers/spikes/2026-09-29-universal-control.md), shared by
/// `UniversalControlLogTests` and `UniversalControlPlacementTests` so
/// neither test file reaches into the other for fixture data.
enum UniversalControlFixtureRoles {
    static let localDevice = "6A19903B-D301-430D-BCA2-E11D75649E79"
    static let odyssey = "82EC66E0-6457-473F-9493-EA95C344DC1E"
    static let lgDisplay = "03FB9F76-0120-4A09-8532-B8A1D0FC4330"
    static let rtk = "8846F4A8-F7E6-4EC9-A431-5658A12817E0"
    static let remoteDevice = "44AD1684-0407-46D7-BDC5-946B193935C1"
    static let remoteDisplay = "42395654-F779-4A3D-AF08-E594EADCE41A"
    static let olderMac = "AE87C1AE-2AE0-4211-8E4C-476D44BA71C9"
    /// The remote Mac's built-in panel: its newest link is a stale,
    /// superseded transaction that predates the device's newest
    /// transaction, so R4′ excludes it. Not in the brief's Roles list —
    /// see `remoteBuiltInPanelIsExcluded`.
    static let remoteBuiltInPanel = "2B9B0CEB-0893-4110-A58F-3CBA4FE8EB24"
}
