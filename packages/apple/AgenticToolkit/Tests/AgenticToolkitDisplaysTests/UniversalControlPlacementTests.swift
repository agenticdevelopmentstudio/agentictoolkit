import Foundation
import Testing
@testable import AgenticToolkitDisplays

@MainActor @Suite struct UniversalControlPlacementTests {
    // Shared with UniversalControlLogTests via UniversalControlFixtureRoles.swift,
    // so neither test file reaches into the other for fixture data.
    private typealias Roles = UniversalControlFixtureRoles

    private let localDisplays: Set<String> = [Roles.odyssey, Roles.lgDisplay]

    private func placement() throws -> UniversalControlPlacement {
        let url = try #require(
            Bundle(for: FixtureAnchor.self).url(forResource: "universalcontrol-configuration", withExtension: "plist")
        )
        return UniversalControlPlacement(plistURL: url, localDevice: Roles.localDevice)
    }

    // R4′: a remote display qualifies only if its newest link timestamp
    // equals its device's newest link timestamp over every link mentioning
    // that device — i.e. it was part of the device's most recent
    // transaction. On the fixture, only `remoteDisplay` qualifies.
    @Test func listsTheRemoteScreen() throws {
        let screens = try placement().remoteScreens(localDisplayUUIDs: localDisplays)
        #expect(screens == [
            RemoteScreen(id: RemoteScreenID(device: Roles.remoteDevice, display: Roles.remoteDisplay))
        ])
    }

    // R4′: the remote Mac's built-in panel (`remoteBuiltInPanel`) was last
    // linked to the Odyssey in an older, superseded transaction (entry ts
    // 812211046774), while the device's newest transaction (ts
    // 812301516709, the head entry) only involves `remoteDisplay`. So the
    // panel's newest link timestamp does not equal its device's newest link
    // timestamp, and it is excluded.
    @Test func remoteBuiltInPanelIsExcluded() throws {
        let screens = try placement().remoteScreens(localDisplayUUIDs: localDisplays)
        let panel = RemoteScreen(id: RemoteScreenID(device: Roles.remoteDevice, display: Roles.remoteBuiltInPanel))
        #expect(!screens.contains(panel))
    }

    @Test func readsTheRemoteAnchorAgainstTheOdyssey() throws {
        let id = RemoteScreenID(device: Roles.remoteDevice, display: Roles.remoteDisplay)
        let anchor = try #require(
            try placement().placement(of: id, localDisplayUUIDs: localDisplays, preferredParentUUID: Roles.odyssey)
        )
        #expect(anchor.parent == .local(DisplayIdentity(uuid: Roles.odyssey, vendor: 0, model: 0, serial: 0)))
        #expect(anchor.edge == .left)
        #expect(anchor.parentFraction == 1.0)
        #expect(abs(anchor.childFraction - 18659.0 / 65535.0) < 1e-9)
    }

    /// The batch read agrees with `remoteScreens` + `placement(of:)`, keeps
    /// their order, and appends requested screens it does not list (M8).
    @Test func batchPlacementsMatchTheIndividualReads() throws {
        let subject = try placement()
        let panel = RemoteScreenID(device: Roles.remoteDevice, display: Roles.remoteBuiltInPanel)
        let preferred: (RemoteScreenID) -> String? = { $0 == panel ? Roles.odyssey : Roles.lgDisplay }
        let batch = try subject.placements(
            including: [panel], localDisplayUUIDs: localDisplays, preferredParentUUID: preferred
        )
        let ids = try subject.remoteScreens(localDisplayUUIDs: localDisplays).map(\.id) + [panel]
        let individual = try ids.map { id in
            RemoteScreenAnchor(screen: id, anchor: try subject.placement(
                of: id, localDisplayUUIDs: localDisplays, preferredParentUUID: preferred(id)
            ))
        }
        #expect(batch == individual)
        #expect(batch.count == 2)
    }

    // R6: with no preference, the fixture's head entry lists the LG link
    // (edge 0) before the Odyssey link (edge 3), confirmed directly against
    // the fixture bytes (see task-8-report.md), so the LG is the expected
    // parent here, not the Odyssey.
    @Test func withoutPreferenceTakesFirstLink() throws {
        let id = RemoteScreenID(device: Roles.remoteDevice, display: Roles.remoteDisplay)
        let anchor = try #require(
            try placement().placement(of: id, localDisplayUUIDs: localDisplays, preferredParentUUID: nil)
        )
        #expect(anchor.parent == .local(DisplayIdentity(uuid: Roles.lgDisplay, vendor: 0, model: 0, serial: 0)))
        #expect(anchor.edge == .bottom)
        #expect(anchor.parentFraction == 0.5)
        #expect(anchor.childFraction == 0.5)
    }

    /// The local displays are read per call: a call made while only the
    /// RTK is online (it touches no remote screen) finds nothing, while the
    /// same adapter still finds the screen when the Odyssey and LG are back.
    @Test func localDisplaysArePassedPerCall() throws {
        let subject = try placement()
        let id = RemoteScreenID(device: Roles.remoteDevice, display: Roles.remoteDisplay)
        #expect(try subject.remoteScreens(localDisplayUUIDs: [Roles.rtk]).isEmpty)
        #expect(try subject.placement(of: id, localDisplayUUIDs: [Roles.rtk], preferredParentUUID: nil) == nil)
        #expect(try subject.remoteScreens(localDisplayUUIDs: localDisplays) == [RemoteScreen(id: id)])
    }

    // MARK: - forThisMac rule (temporary files only; never the real ByHost plist)

    private func temporaryPlist(_ contents: Data?) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("com.apple.universalcontrol.test.plist")
        if let contents { try contents.write(to: url) }
        return url
    }

    @Test func absentPlistGivesNil() throws {
        let url = try temporaryPlist(nil)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try UniversalControlPlacement.forPlist(at: url, localDisplayUUIDs: localDisplays) == nil)
    }

    @Test func corruptPlistThrows() throws {
        let url = try temporaryPlist(Data("not a property list".utf8))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(throws: RemoteScreenError.unreadable("\(url.lastPathComponent): no Configuration")) {
            try UniversalControlPlacement.forPlist(at: url, localDisplayUUIDs: localDisplays)
        }
    }

    @Test func plistWithoutThisMacsDisplaysGivesNil() throws {
        let fixture = try #require(
            Bundle(for: FixtureAnchor.self).url(forResource: "universalcontrol-configuration", withExtension: "plist")
        )
        let url = try temporaryPlist(try Data(contentsOf: fixture))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try UniversalControlPlacement.forPlist(at: url, localDisplayUUIDs: ["NOT-A-UC-DISPLAY"]) == nil)
        let found = try #require(try UniversalControlPlacement.forPlist(at: url, localDisplayUUIDs: localDisplays))
        #expect(found.localDevice == Roles.localDevice)
    }

    @Test func writeIsRefusedUntilVerified() throws {
        let subject = try placement()
        guard case .unsupported = subject.support else { return }   // becomes a write test once supported
        let id = RemoteScreenID(device: Roles.remoteDevice, display: Roles.remoteDisplay)
        #expect(throws: RemoteScreenError.self) {
            try subject.setPlacement(
                Anchor(
                    parent: .local(DisplayIdentity(uuid: Roles.odyssey, vendor: 0, model: 0, serial: 0)),
                    edge: .left, parentFraction: 0.5, childFraction: 0
                ),
                for: id, localDisplayUUIDs: localDisplays
            )
        }
    }

    // R3: an older Mac (olderMac) also used the LG, but its newest record
    // long predates this Mac's, so the newest-record rule still resolves to
    // this Mac's device id.
    @Test func localDeviceRuleIgnoresAnOlderMacThatSharedTheLG() throws {
        let log = try UniversalControlLog(configuration: UniversalControlLogTests.fixture())
        let device = UniversalControlPlacement.localDeviceID(
            in: log, localDisplayUUIDs: [Roles.odyssey, Roles.lgDisplay, Roles.rtk]
        )
        #expect(device == Roles.localDevice)
    }

    // R5: the fixture's actual edge-3 head record is the ground truth for
    // the mapping table.
    @Test func fixtureEdgeThreeHeadRecordMapsToLeft() throws {
        let log = try UniversalControlLog(configuration: UniversalControlLogTests.fixture())
        let link = try #require(log.currentLinks(of: Roles.remoteDisplay).first { $0.edge == 3 })
        let remote = RemoteScreenID(device: Roles.remoteDevice, display: Roles.remoteDisplay)
        let anchor = try #require(UniversalControlPlacement.anchor(
            from: link, remote: remote, localDevice: Roles.localDevice,
            localDisplayUUIDs: [Roles.odyssey, Roles.lgDisplay]
        ))
        #expect(anchor.edge == .left)
        #expect(anchor.parentFraction == 1.0)
        #expect(abs(anchor.childFraction - 18659.0 / 65535.0) < 1e-9)
    }

    // R5: round trip through `link(...)` and back through `anchor(from:...)`
    // for all 4 edges, with the remote on each side of the lexicographic
    // device-id order. Fractions 0.5 and 1.0 are used because they land
    // exactly on `fraction(_:)`'s snap targets, so the round trip is exact.
    @Test func roundTripsAllEdgesBothDeviceOrders() throws {
        let smallerDevice = "10000000-0000-0000-0000-000000000000"
        let largerDevice = "90000000-0000-0000-0000-000000000000"
        let localDisplay = "AAAAAAAA-0000-0000-0000-000000000000"
        let remoteDisplay = "BBBBBBBB-0000-0000-0000-000000000000"

        for edge in DisplayEdge.allCases {
            for remoteDeviceID in [smallerDevice, largerDevice] {
                let localDeviceID = remoteDeviceID == smallerDevice ? largerDevice : smallerDevice
                let remote = RemoteScreenID(device: remoteDeviceID, display: remoteDisplay)
                let original = Anchor(
                    parent: .local(DisplayIdentity(uuid: localDisplay, vendor: 0, model: 0, serial: 0)),
                    edge: edge, parentFraction: 0.5, childFraction: 1.0
                )
                let link = UniversalControlPlacement.link(
                    remote: remote, localDevice: localDeviceID, localDisplay: localDisplay,
                    anchor: original, timestamp: 1
                )
                let roundTripped = try #require(UniversalControlPlacement.anchor(
                    from: link, remote: remote, localDevice: localDeviceID, localDisplayUUIDs: [localDisplay]
                ))
                #expect(roundTripped == original)
            }
        }
    }

    // Covers quantisation: 0.3 is far from every snap target (0, 0.5, 1),
    // so it round-trips through offset(_:)/fraction(_:) inexactly. The
    // result must land within one quantisation step (1/65535), not exactly.
    @Test func roundTripsNonSnappedFractionWithinQuantization() throws {
        let smallerDevice = "10000000-0000-0000-0000-000000000000"
        let largerDevice = "90000000-0000-0000-0000-000000000000"
        let localDisplay = "AAAAAAAA-0000-0000-0000-000000000000"
        let remoteDisplayID = "BBBBBBBB-0000-0000-0000-000000000000"
        let remote = RemoteScreenID(device: smallerDevice, display: remoteDisplayID)
        let original = Anchor(
            parent: .local(DisplayIdentity(uuid: localDisplay, vendor: 0, model: 0, serial: 0)),
            edge: .left, parentFraction: 0.3, childFraction: 0.3
        )
        let link = UniversalControlPlacement.link(
            remote: remote, localDevice: largerDevice, localDisplay: localDisplay, anchor: original, timestamp: 1
        )
        let roundTripped = try #require(UniversalControlPlacement.anchor(
            from: link, remote: remote, localDevice: largerDevice, localDisplayUUIDs: [localDisplay]
        ))
        #expect(abs(roundTripped.parentFraction - 0.3) < 1.0 / 65535)
        #expect(abs(roundTripped.childFraction - 0.3) < 1.0 / 65535)
    }
}
