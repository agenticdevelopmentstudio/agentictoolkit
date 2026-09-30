import CoreGraphics
import Testing
@testable import AgenticToolkitDisplays

/// Test double for `RemoteScreenPlacement`. `failRead` makes the read
/// throw and `failWrite` makes `setPlacement` throw; `written` records every
/// successful `setPlacement` call. `candidates` lists, per screen, every
/// anchor it currently has (one per local display it touches); a read
/// returns the one whose parent is the preferred parent, else the first.
/// `readUUIDs` records the local display UUIDs each read got, one entry per
/// read of the backing store.
@MainActor
private final class FakeRemote: RemoteScreenPlacement {
    var support: RemoteSupport = .supported
    var screens: [RemoteScreen] = []
    var candidates: [RemoteScreenID: [Anchor]] = [:]
    var failRead: RemoteScreenError?
    var failWrite: RemoteScreenError?
    private(set) var written: [RemoteScreenID: Anchor] = [:]
    private(set) var readUUIDs: [Set<String>] = []

    var anchors: [RemoteScreenID: Anchor] {
        get { candidates.compactMapValues(\.first) }
        set { candidates = newValue.mapValues { [$0] } }
    }

    func placements(
        including extra: [RemoteScreenID], localDisplayUUIDs: Set<String>,
        preferredParentUUID: (RemoteScreenID) -> String?
    ) throws(RemoteScreenError) -> [RemoteScreenAnchor] {
        readUUIDs.append(localDisplayUUIDs)
        if let failRead { throw failRead }
        var ids = screens.map(\.id)
        for id in extra where !ids.contains(id) { ids.append(id) }
        return ids.map { id in
            let options = candidates[id] ?? []
            let preferred = options.first { $0.parent == .local(Self.identity(preferredParentUUID(id))) }
            return RemoteScreenAnchor(screen: id, anchor: preferred ?? options.first)
        }
    }

    func setPlacement(
        _ anchor: Anchor, for screen: RemoteScreenID, localDisplayUUIDs: Set<String>
    ) throws(RemoteScreenError) {
        if let failWrite { throw failWrite }
        written[screen] = anchor
    }

    private static func identity(_ uuid: String?) -> DisplayIdentity {
        DisplayIdentity(uuid: uuid, vendor: .max, model: .max, serial: .max)
    }
}

@MainActor @Suite struct LayoutServiceTests {
    let system = FakeDisplaySystem.desk()
    let store = InMemoryDocumentStore()
    let odyssey = DisplayIdentity(uuid: "ODYSSEY", vendor: 0, model: 0, serial: 3)
    let lgIdentity = DisplayIdentity(uuid: "LG", vendor: 0, model: 0, serial: 2)

    private func service(remote: RemoteScreenPlacement? = nil) throws -> LayoutService {
        try LayoutService(system: system, store: store, remote: remote)
    }

    @Test func captureCurrentSavesAnAnchoredLayout() throws {
        let service = try service()
        let layout = try service.captureCurrent(name: "Desk", autoApply: true, withModes: false)
        #expect(layout.displaySetID == "LG+ODYSSEY+RTK")
        #expect(layout.main == odyssey)
        #expect(layout.localAnchors.count == 2)
        #expect(store.document.layouts == [layout])
        #expect(service.isActive(layout))
    }

    @Test func applyMovesDisplaysBackAfterAnExternalChange() throws {
        let service = try service()
        let layout = try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        try system.apply([.origin(2, CGPoint(x: -3840, y: 0))])
        #expect(!service.isActive(layout))
        let report = try service.apply(layout)
        #expect(report.arranged)
        #expect(system.onlineDisplays().first { $0.id == 2 }?.bounds.origin == CGPoint(x: -3840, y: -615))
        #expect(service.isActive(layout))
    }

    @Test func applyKeepsAnchorsWhenResolutionChanged() throws {
        let service = try service()
        var layout = try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        layout.placements = layout.placements.map { placement in
            guard placement.display == .local(lgIdentity) else { return placement }
            var edited = placement
            edited.anchor = Anchor(parent: .local(odyssey), edge: .left, parentFraction: 0.5, childFraction: 1)
            return edited
        }
        try service.save(layout)
        let smaller = try #require(system.modes(for: 2).first { $0.pointSize.width == 2560 })
        try system.apply([.mode(2, smaller)])
        _ = try service.apply(layout)
        #expect(system.onlineDisplays().first { $0.id == 2 }?.bounds.origin == CGPoint(x: -2560, y: -360))
    }

    @Test func applyWithModesSetsModesFirstThenSolvesWithNewSizes() throws {
        let service = try service()
        var layout = try service.captureCurrent(name: "Desk", autoApply: false, withModes: true)
        layout.placements = layout.placements.map { placement in
            guard placement.display == .local(lgIdentity) else { return placement }
            var edited = placement
            edited.mode = ModeSpec(width: 2560, height: 1440, refreshRate: 60, isHiDPI: true)
            edited.anchor = Anchor(parent: .local(odyssey), edge: .left, parentFraction: 0.5, childFraction: 1)
            return edited
        }
        let report = try service.apply(layout)
        #expect(report.changedModes == [2])
        let expectedBounds = CGRect(x: -2560, y: -360, width: 2560, height: 1440)
        #expect(system.onlineDisplays().first { $0.id == 2 }?.bounds == expectedBounds)
        #expect(service.recentModes(for: lgIdentity).first?.width == 2560)
    }

    /// A store failure while recording recents is reported, never thrown:
    /// the modes and the arrangement have already been applied (M1).
    @Test func recentsFailureIsReportedAfterArranging() throws {
        let service = try service()
        var layout = try service.captureCurrent(name: "Desk", autoApply: false, withModes: true)
        layout.placements = layout.placements.map { placement in
            guard placement.display == .local(lgIdentity) else { return placement }
            var edited = placement
            edited.mode = ModeSpec(width: 2560, height: 1440, refreshRate: 60, isHiDPI: true)
            edited.anchor = Anchor(parent: .local(odyssey), edge: .left, parentFraction: 0.5, childFraction: 1)
            return edited
        }
        store.failNextSave = .ioError("disk full")
        let report = try service.apply(layout)
        #expect(report.changedModes == [2])
        #expect(report.arranged)
        #expect(report.recentsError == .store(.ioError("disk full")))
        let expectedBounds = CGRect(x: -2560, y: -360, width: 2560, height: 1440)
        #expect(system.onlineDisplays().first { $0.id == 2 }?.bounds == expectedBounds)
        #expect(service.recentModes(for: lgIdentity).isEmpty)
    }

    @Test func planRefusesADifferentDisplaySet() throws {
        let service = try service()
        let layout = try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        system.replaceDisplays(system.onlineDisplays().filter { $0.id != 8 })
        #expect(throws: LayoutServiceError.displaySetMismatch(expected: "LG+ODYSSEY+RTK", actual: "LG+ODYSSEY")) {
            try service.plan(layout)
        }
        #expect(throws: LayoutServiceError.displaySetMismatch(expected: "LG+ODYSSEY+RTK", actual: "LG+ODYSSEY")) {
            try service.remoteDrift(layout)
        }
    }

    @Test func captureThatDoesNotSolveIsRefusedNotSaved() throws {
        let service = try service()
        // RTK beside the Odyssey's left edge, on top of the LG: every display
        // touches main, but the anchors solve to overlapping displays.
        try system.apply([.origin(8, CGPoint(x: -2560, y: 0))])
        let error = #expect(throws: LayoutServiceError.self) {
            try service.captureCurrent(name: "Overlap", autoApply: false, withModes: false)
        }
        guard case .unsolvableCapture(.overlap) = error else {
            Issue.record("expected unsolvableCapture(.overlap), got \(String(describing: error))")
            return
        }
        #expect(service.layouts.isEmpty)
    }

    @Test func identicalDisplaysAreRefusedNotStacked() throws {
        let service = try service()
        let layout = try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        let twin = FakeDisplaySystem.makeDisplay(
            id: 9, uuid: "RTK", bounds: CGRect(x: 3733, y: 2160, width: 2560, height: 1440)
        )
        system.replaceDisplays(system.onlineDisplays() + [twin])
        let rtk = DisplayIdentity(uuid: "RTK", vendor: 0, model: 0, serial: 0)
        #expect(throws: LayoutServiceError.ambiguousDisplays([rtk])) {
            try service.captureCurrent(name: "Twins", autoApply: false, withModes: false)
        }
        #expect(throws: LayoutServiceError.ambiguousDisplays([rtk])) { try service.plan(layout) }
        #expect(throws: LayoutServiceError.ambiguousDisplays([rtk])) { try service.remoteDrift(layout) }
        #expect(service.layouts.map(\.name) == ["Desk"])
    }

    @Test func autoApplyIsUniquePerDisplaySet() throws {
        let service = try service()
        let first = try service.captureCurrent(name: "One", autoApply: true, withModes: false)
        let second = try service.captureCurrent(name: "Two", autoApply: true, withModes: false)
        #expect(service.layout(id: first.id)?.autoApply == false)
        #expect(service.layout(id: second.id)?.autoApply == true)
    }

    @Test func namesAreUniqueCaseInsensitively() throws {
        let service = try service()
        _ = try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        #expect(throws: LayoutServiceError.duplicateName("desk")) {
            try service.captureCurrent(name: "desk", autoApply: false, withModes: false)
        }
        let other = try service.captureCurrent(name: "Other", autoApply: false, withModes: false)
        #expect(throws: LayoutServiceError.duplicateName("Desk")) { try service.rename(other.id, to: "Desk") }
    }

    @Test func duplicateRenameDelete() throws {
        let service = try service()
        let desk = try service.captureCurrent(name: "Desk", autoApply: true, withModes: false)
        let copy = try service.duplicate(desk.id)
        #expect(copy.name == "Desk copy")
        #expect(copy.autoApply == false)
        try service.rename(copy.id, to: "Evening")
        #expect(service.layout(named: "evening")?.id == copy.id)
        try service.delete(desk.id)
        #expect(service.layouts.map(\.name) == ["Evening"])
        #expect(throws: LayoutServiceError.notFound(desk.id.uuidString)) { try service.delete(desk.id) }
    }

    @Test func storeFailureSurfacesAndStateIsUnchanged() throws {
        let service = try service()
        store.failNextSave = .ioError("disk full")
        #expect(throws: LayoutServiceError.store(.ioError("disk full"))) {
            try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        }
        #expect(service.layouts.isEmpty)
    }

    @Test func labelsPersist() throws {
        let service = try service()
        try service.setLabel("Desk", width: 3840, height: 2160, refreshRate: nil)
        let spec = ModeSpec(width: 3840, height: 2160, refreshRate: 60, isHiDPI: false)
        #expect(service.labels.label(for: spec) == "Desk")
        #expect(store.document.labels.count == 1)
    }

    // MARK: - Remote (Universal Control)

    @Test func captureIncludesRemotePlacements() throws {
        let remote = FakeRemote()
        let screenID = RemoteScreenID(device: "MacBookPro", display: "Built-in")
        let anchor = Anchor(parent: .local(odyssey), edge: .right, parentFraction: 0.5, childFraction: 0)
        remote.screens = [RemoteScreen(id: screenID)]
        remote.anchors = [screenID: anchor]
        let service = try service(remote: remote)
        let layout = try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        let placement = try #require(layout.placements.first { $0.display == .remote(screenID) })
        #expect(placement.anchor == anchor)
        #expect(placement.mode == nil)
        #expect(remote.readUUIDs == [["ODYSSEY", "LG", "RTK"]])
    }

    /// Capture and plan each read the remote store once, however many
    /// remote screens there are (M8).
    @Test func captureAndPlanReadTheRemoteStoreOnce() throws {
        let remote = FakeRemote()
        let first = RemoteScreenID(device: "MacBookPro", display: "Built-in")
        let second = RemoteScreenID(device: "MacBookPro", display: "Studio")
        let anchor = Anchor(parent: .local(odyssey), edge: .right, parentFraction: 0.5, childFraction: 0)
        remote.screens = [RemoteScreen(id: first), RemoteScreen(id: second)]
        remote.anchors = [first: anchor, second: anchor]
        let service = try service(remote: remote)
        let layout = try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        #expect(remote.readUUIDs.count == 1)
        _ = try service.plan(layout)
        #expect(remote.readUUIDs.count == 2)
    }

    @Test func remoteWriteFailureIsReportedTyped() throws {
        let remote = FakeRemote()
        let screenID = RemoteScreenID(device: "MacBookPro", display: "Built-in")
        remote.screens = [RemoteScreen(id: screenID)]
        let service = try service(remote: remote)
        var layout = try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        let anchor = Anchor(parent: .local(odyssey), edge: .right, parentFraction: 0.5, childFraction: 0)
        layout.placements = layout.placements.map { placement in
            guard placement.display == .remote(screenID) else { return placement }
            var edited = placement
            edited.anchor = anchor
            return edited
        }
        remote.failWrite = .unreadable("locked")
        #expect(try service.apply(layout).remote == .failed(.unreadable("locked")))
    }

    /// The remote screen touches both the Odyssey (main) and the LG. The
    /// layout anchors it to the LG, so the current placement must be read
    /// against the LG too; read against main it would look like a change.
    @Test func pendingRemoteChangesCompareAgainstTheAnchorsParent() throws {
        let remote = FakeRemote()
        let screenID = RemoteScreenID(device: "MacBookPro", display: "Built-in")
        let onOdyssey = Anchor(parent: .local(odyssey), edge: .right, parentFraction: 0.5, childFraction: 0)
        let onLG = Anchor(parent: .local(lgIdentity), edge: .top, parentFraction: 0.5, childFraction: 0.5)
        remote.screens = [RemoteScreen(id: screenID)]
        remote.candidates = [screenID: [onOdyssey, onLG]]
        let service = try service(remote: remote)
        var layout = try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        #expect(layout.placements.first { $0.display == .remote(screenID) }?.anchor == onOdyssey)
        layout.placements = layout.placements.map { placement in
            guard placement.display == .remote(screenID) else { return placement }
            var edited = placement
            edited.anchor = onLG
            return edited
        }
        #expect(try service.plan(layout).remoteChanges.isEmpty)
        #expect(try service.remoteDrift(layout).isEmpty)
    }

    @Test func remoteDriftIsReportedEvenWhenUnsupported() throws {
        let remote = FakeRemote()
        let screenID = RemoteScreenID(device: "MacBookPro", display: "Built-in")
        remote.support = .unsupported("pending verification")
        remote.screens = [RemoteScreen(id: screenID)]
        let captured = Anchor(parent: .local(odyssey), edge: .right, parentFraction: 0.5, childFraction: 0)
        remote.anchors = [screenID: captured]
        let service = try service(remote: remote)
        let layout = try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        #expect(try service.remoteDrift(layout).isEmpty)
        remote.anchors = [screenID: Anchor(parent: .local(odyssey), edge: .right, parentFraction: 0, childFraction: 0)]
        #expect(try service.remoteDrift(layout) == [screenID])
        #expect(try service.plan(layout).remoteChanges.isEmpty)
    }

    @Test func remoteDriftWithoutAnAdapterIsEmpty() throws {
        let service = try service()
        let layout = try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        #expect(try service.remoteDrift(layout).isEmpty)
    }

    @Test func remoteReadFailureSurfaces() throws {
        let remote = FakeRemote()
        remote.failRead = .unreadable("x")
        let service = try service(remote: remote)
        #expect(throws: LayoutServiceError.remote(.unreadable("x"))) {
            try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        }
        #expect(service.layouts.isEmpty)
    }

    @Test func unsupportedRemoteIsReportedNotWritten() throws {
        let remote = FakeRemote()
        let screenID = RemoteScreenID(device: "MacBookPro", display: "Built-in")
        remote.support = .unsupported("pending verification")
        remote.screens = [RemoteScreen(id: screenID)]
        let service = try service(remote: remote)
        var layout = try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        layout.placements = layout.placements.map { placement in
            guard placement.display == .remote(screenID) else { return placement }
            var edited = placement
            edited.anchor = Anchor(parent: .local(odyssey), edge: .right, parentFraction: 0.5, childFraction: 0)
            return edited
        }
        try service.save(layout)
        #expect(try service.plan(layout).remoteChanges.isEmpty)
        let report = try service.apply(layout)
        #expect(report.remote == .unsupported("pending verification"))
        #expect(remote.written.isEmpty)
    }

    @Test func supportedRemoteWritesChangedAnchors() throws {
        let remote = FakeRemote()
        let screenID = RemoteScreenID(device: "MacBookPro", display: "Built-in")
        remote.support = .supported
        remote.screens = [RemoteScreen(id: screenID)]
        let service = try service(remote: remote)
        var layout = try service.captureCurrent(name: "Desk", autoApply: false, withModes: false)
        let anchor = Anchor(parent: .local(odyssey), edge: .right, parentFraction: 0.5, childFraction: 0)
        layout.placements = layout.placements.map { placement in
            guard placement.display == .remote(screenID) else { return placement }
            var edited = placement
            edited.anchor = anchor
            return edited
        }
        try service.save(layout)
        #expect(try service.plan(layout).remoteChanges == [screenID: anchor])
        let report = try service.apply(layout)
        #expect(report.remote == .applied(1))
        #expect(remote.written == [screenID: anchor])
    }
}
