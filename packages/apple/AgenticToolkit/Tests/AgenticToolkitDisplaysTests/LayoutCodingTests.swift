import Foundation
import Testing
@testable import AgenticToolkitDisplays

@Suite struct LayoutCodingTests {
    static let odyssey = DisplayIdentity(uuid: "ODYSSEY", vendor: 0, model: 0, serial: 0)
    static let lgDisplay = DisplayIdentity(uuid: "LG", vendor: 0, model: 0, serial: 0)
    static let remote = RemoteScreenID(device: "DEV", display: "SCR")

    static func deskLayout() -> Layout {
        Layout(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Desk",
               displaySetID: "LG+ODYSSEY", main: odyssey,
               placements: [
                   DisplayPlacement(display: .local(odyssey), anchor: nil, mode: nil),
                   DisplayPlacement(
                       display: .local(lgDisplay),
                       anchor: Anchor(parent: .local(odyssey), edge: .left, parentFraction: 0.5, childFraction: 1),
                       mode: ModeSpec(width: 3840, height: 2160, refreshRate: 60, isHiDPI: false)),
                   DisplayPlacement(
                       display: .remote(remote),
                       anchor: Anchor(parent: .local(odyssey), edge: .left, parentFraction: 0.5, childFraction: 0),
                       mode: nil)
               ],
               applyModes: true, autoApply: true)
    }

    @Test func splitsLocalAndRemoteAnchors() {
        let layout = Self.deskLayout()
        #expect(layout.localAnchors.keys.sorted { $0.key < $1.key } == [Self.lgDisplay])
        #expect(layout.remoteAnchors[Self.remote]?.childFraction == 0)
        #expect(layout.mode(for: Self.lgDisplay)?.width == 3840)
    }

    @Test func documentRoundTrip() throws {
        var document = DisplayDocument()
        document.layouts = [Self.deskLayout()]
        document.labels = [ModeLabelOverride(width: 3840, height: 2160, refreshRate: nil, label: "Desk")]
        document.recentModes = ["LG": [ModeSpec(width: 2560, height: 1440, refreshRate: 60, isHiDPI: true)]]
        let data = try JSONEncoder().encode(document)
        #expect(try JSONDecoder().decode(DisplayDocument.self, from: data) == document)
    }

    @Test func missingKeysDecodeToDefaults() throws {
        let document = try JSONDecoder().decode(DisplayDocument.self, from: Data(#"{"version":1}"#.utf8))
        #expect(document == DisplayDocument())
        #expect(document.preferences.autoApplyEnabled)
    }
}
