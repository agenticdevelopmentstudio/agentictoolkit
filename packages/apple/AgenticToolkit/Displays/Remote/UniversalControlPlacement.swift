import Foundation
import IOKit

/// Universal Control adapter. Reads (and, once verified, writes) this Mac's
/// ByHost UC arrangement. Nothing else in the framework knows UC exists.
@MainActor
public final class UniversalControlPlacement: RemoteScreenPlacement {
    /// Set from the spike verdict (docs/superpowers/spikes/2026-09-29-universal-control.md).
    /// The verdict is `pending write test`; the controller changes this once verified.
    public static let verifiedWriteSupport: RemoteSupport = .unsupported("pending verification")

    public let plistURL: URL
    /// This Mac's UC device id: fixed per machine, so it is stored. The
    /// displays and the preferred parent change at runtime and are passed
    /// per call instead.
    public let localDevice: String

    public init(plistURL: URL, localDevice: String) {
        self.plistURL = plistURL
        self.localDevice = localDevice
    }

    /// The adapter for this Mac, or nil when UC has never been configured
    /// here: the ByHost plist is absent, or no device in it has this Mac's
    /// displays. Any other failure (the platform UUID or the plist cannot
    /// be read, or the plist is malformed) throws `RemoteScreenError.unreadable`.
    /// The local device is found by the spike's local-device rule (R3),
    /// against the displays online right now.
    public static func forThisMac() throws -> UniversalControlPlacement? {
        guard let host = platformUUID() else { throw RemoteScreenError.unreadable("platform UUID unavailable") }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/ByHost/com.apple.universalcontrol.\(host).plist")
        let localDisplayUUIDs = Set(CoreGraphicsDisplaySystem().onlineDisplays().compactMap(\.identity.uuid))
        return try forPlist(at: url, localDisplayUUIDs: localDisplayUUIDs)
    }

    /// `forThisMac()`'s rule for an explicit plist, so it can be tested
    /// against temporary files.
    static func forPlist(at url: URL, localDisplayUUIDs: Set<String>) throws -> UniversalControlPlacement? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let log = try readLog(url)
        guard let device = localDeviceID(in: log, localDisplayUUIDs: localDisplayUUIDs) else { return nil }
        return UniversalControlPlacement(plistURL: url, localDevice: device)
    }

    public var support: RemoteSupport { Self.verifiedWriteSupport }

    /// Every remote screen currently anchored against one of this Mac's local
    /// displays (R4, amended by R4′): `device != localDevice`; at least one
    /// of that display's current links pairs it with `(localDevice, d)` for
    /// `d` in `localDisplayUUIDs`; and that display's newest link timestamp
    /// equals its device's newest link timestamp, taken over every link that
    /// mentions that device (R4′) — i.e. the display was part of the
    /// device's most recent transaction. Ordered by first appearance while
    /// walking heap entries newest-first by entry timestamp.
    ///
    /// Trade-off (R4′): UC keeps links for remote displays that are no
    /// longer active, such as the remote Mac's built-in panel while the lid
    /// is closed. This rule excludes those, but it also excludes a second
    /// remote display that is genuinely active and simply has not moved
    /// recently — it stays hidden until it is next moved, because its links
    /// then predate its device's newest transaction.
    ///
    /// Not part of `RemoteScreenPlacement` (the batch `placements` covers
    /// it); kept here because the R4/R4′ membership tests pin this rule on
    /// the fixture independently of anchor reading.
    public func remoteScreens(localDisplayUUIDs: Set<String>) throws(RemoteScreenError) -> [RemoteScreen] {
        screens(in: try Self.readLog(plistURL), localDisplayUUIDs: localDisplayUUIDs).map(RemoteScreen.init)
    }

    /// The remote screen's anchor against one of `localDisplayUUIDs`. When it
    /// touches several, the one against `preferredParentUUID` wins (R6).
    public func placement(
        of screen: RemoteScreenID, localDisplayUUIDs: Set<String>, preferredParentUUID: String?
    ) throws(RemoteScreenError) -> Anchor? {
        placement(
            of: screen, in: try Self.readLog(plistURL),
            localDisplayUUIDs: localDisplayUUIDs, preferredParentUUID: preferredParentUUID
        )
    }

    /// `remoteScreens` then `placement(of:)` for each of them and for each of
    /// `including` not already listed, from one read of the plist.
    public func placements(
        including screens: [RemoteScreenID], localDisplayUUIDs: Set<String>,
        preferredParentUUID: (RemoteScreenID) -> String?
    ) throws(RemoteScreenError) -> [RemoteScreenAnchor] {
        let log = try Self.readLog(plistURL)
        var ids = self.screens(in: log, localDisplayUUIDs: localDisplayUUIDs)
        for id in screens where !ids.contains(id) { ids.append(id) }
        return ids.map { id in
            RemoteScreenAnchor(screen: id, anchor: placement(
                of: id, in: log, localDisplayUUIDs: localDisplayUUIDs, preferredParentUUID: preferredParentUUID(id)
            ))
        }
    }

    private func screens(in log: UniversalControlLog, localDisplayUUIDs: Set<String>) -> [RemoteScreenID] {
        let allLinks = log.entries.flatMap(\.links)
        // Ties on entry timestamp are broken by the original heap index,
        // ascending, so the walk order (and hence `seen`'s first-appearance
        // order) is stable rather than depending on `sorted`'s tie behavior.
        let orderedEntries = log.entries.enumerated()
            .sorted { lhs, rhs in
                lhs.element.timestamp != rhs.element.timestamp
                    ? lhs.element.timestamp > rhs.element.timestamp
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
        var seen: [RemoteScreenID] = []
        for entry in orderedEntries {
            for link in entry.links {
                for side in [(link.deviceA, link.displayA), (link.deviceB, link.displayB)]
                where side.0 != localDevice {
                    let candidate = RemoteScreenID(device: side.0, display: side.1)
                    guard !seen.contains(candidate) else { continue }
                    guard touchesLocalDisplay(candidate, in: log, localDisplayUUIDs: localDisplayUUIDs) else {
                        continue
                    }
                    guard isPartOfDevicesNewestTransaction(candidate, in: allLinks) else { continue }
                    seen.append(candidate)
                }
            }
        }
        return seen
    }

    private func placement(
        of screen: RemoteScreenID, in log: UniversalControlLog,
        localDisplayUUIDs: Set<String>, preferredParentUUID: String?
    ) -> Anchor? {
        let candidates = log.currentLinks(of: screen.display).compactMap {
            Self.anchor(from: $0, remote: screen, localDevice: localDevice, localDisplayUUIDs: localDisplayUUIDs)
        }
        if let preferredParentUUID,
           let preferred = candidates.first(where: { isParent($0, uuid: preferredParentUUID) }) {
            return preferred
        }
        // No preference: the spike gives UC no size data to rank by, so the
        // first candidate in link order stands in for "longest contact" (R6).
        return candidates.first
    }

    public func setPlacement(
        _ anchor: Anchor, for screen: RemoteScreenID, localDisplayUUIDs: Set<String>
    ) throws(RemoteScreenError) {
        guard case .supported = support else {
            if case let .unsupported(reason) = support { throw RemoteScreenError.unsupported(reason) }
            return
        }
        throw RemoteScreenError.unsupported("writer not implemented for this log version")
    }

    // MARK: - R4 / R4′ helpers

    private func touchesLocalDisplay(
        _ candidate: RemoteScreenID, in log: UniversalControlLog, localDisplayUUIDs: Set<String>
    ) -> Bool {
        log.currentLinks(of: candidate.display).contains { link in
            let aIsCandidate = link.deviceA == candidate.device && link.displayA == candidate.display
            let bIsCandidate = link.deviceB == candidate.device && link.displayB == candidate.display
            let otherIsLocal = aIsCandidate
                ? (link.deviceB == localDevice && localDisplayUUIDs.contains(link.displayB))
                : (link.deviceA == localDevice && localDisplayUUIDs.contains(link.displayA))
            return (aIsCandidate || bIsCandidate) && otherIsLocal
        }
    }

    /// R4′: `candidate`'s newest link timestamp (over links pairing its own
    /// device with its own display) must equal `candidate.device`'s newest
    /// link timestamp over every link mentioning that device, on either side,
    /// regardless of display.
    private func isPartOfDevicesNewestTransaction(
        _ candidate: RemoteScreenID, in links: [UniversalControlLink]
    ) -> Bool {
        let displayNewest = links
            .filter { ($0.deviceA == candidate.device && $0.displayA == candidate.display)
                || ($0.deviceB == candidate.device && $0.displayB == candidate.display) }
            .map(\.timestamp).max()
        let deviceNewest = links
            .filter { $0.deviceA == candidate.device || $0.deviceB == candidate.device }
            .map(\.timestamp).max()
        return displayNewest != nil && displayNewest == deviceNewest
    }

    private func isParent(_ anchor: Anchor, uuid: String) -> Bool {
        guard case let .local(identity) = anchor.parent else { return false }
        return identity.uuid == uuid
    }

    // MARK: - Mapping (single source of truth for the spike's findings, R5)

    /// Converts a UC link that pairs `remote` with one of `localDisplayUUIDs`
    /// into an anchor of the remote against that local display. Nil when the
    /// link doesn't pair `remote` with a local display, or the edge is out
    /// of range.
    ///
    /// Edges 1 and 2 carry low confidence in the spike (Findings row 1):
    /// no record in the fixture or live log pins which of "remote above
    /// local" and "remote right of local" is which, so this pair may need
    /// swapping once a write test confirms it.
    static func anchor(
        from link: UniversalControlLink, remote: RemoteScreenID, localDevice: String, localDisplayUUIDs: Set<String>
    ) -> Anchor? {
        let remoteIsA = link.deviceA == remote.device && link.displayA == remote.display
        let remoteIsB = link.deviceB == remote.device && link.displayB == remote.display
        guard remoteIsA != remoteIsB else { return nil }
        guard let edge = mappedEdge(ucEdge: link.edge, remoteIsA: remoteIsA) else { return nil }

        let localDisplay: String
        if remoteIsA {
            guard link.deviceB == localDevice, localDisplayUUIDs.contains(link.displayB) else { return nil }
            localDisplay = link.displayB
        } else {
            guard link.deviceA == localDevice, localDisplayUUIDs.contains(link.displayA) else { return nil }
            localDisplay = link.displayA
        }

        let fractionA = fraction(link.offsetA)
        let fractionB = fraction(link.offsetB)
        let parentFraction = remoteIsA ? fractionB : fractionA
        let childFraction = remoteIsA ? fractionA : fractionB

        return Anchor(
            parent: .local(DisplayIdentity(uuid: localDisplay, vendor: 0, model: 0, serial: 0)),
            edge: edge, parentFraction: parentFraction, childFraction: childFraction
        )
    }

    /// Inverse of `anchor(from:remote:localDevice:localDisplayUUIDs:)`: builds
    /// the UC link for an anchor of `remote` against `localDisplay`. A/B
    /// order follows the lexicographic device-id rule (spike Findings row 3).
    static func link(
        remote: RemoteScreenID, localDevice: String, localDisplay: String, anchor: Anchor, timestamp: Int64
    ) -> UniversalControlLink {
        let remoteIsA = remote.device < localDevice
        let ucEdge = ucEdge(for: anchor.edge, remoteIsA: remoteIsA)
        let remoteOffset = offset(anchor.childFraction)
        let localOffset = offset(anchor.parentFraction)
        if remoteIsA {
            return UniversalControlLink(
                timestamp: timestamp, edge: ucEdge, deviceA: remote.device, displayA: remote.display,
                deviceB: localDevice, displayB: localDisplay, offsetA: remoteOffset, offsetB: localOffset
            )
        }
        return UniversalControlLink(
            timestamp: timestamp, edge: ucEdge, deviceA: localDevice, displayA: localDisplay,
            deviceB: remote.device, displayB: remote.display, offsetA: localOffset, offsetB: remoteOffset
        )
    }

    /// UC edge → anchor edge, from the R5 table. Nil for a UC edge outside
    /// 0...3, the only values UC's `Configuration` records use.
    private static func mappedEdge(ucEdge: Int, remoteIsA: Bool) -> DisplayEdge? {
        switch (ucEdge, remoteIsA) {
        case (0, true): return .bottom
        case (0, false): return .top
        case (1, true): return .top
        case (1, false): return .bottom
        case (2, true): return .right
        case (2, false): return .left
        case (3, true): return .left
        case (3, false): return .right
        default: return nil
        }
    }

    /// Anchor edge → UC edge: the inverse of `mappedEdge(ucEdge:remoteIsA:)`.
    /// Exhaustive over `DisplayEdge`, so a new case fails the build here
    /// instead of silently falling through to a default.
    private static func ucEdge(for edge: DisplayEdge, remoteIsA: Bool) -> Int {
        switch (edge, remoteIsA) {
        case (.bottom, true), (.top, false): return 0
        case (.top, true), (.bottom, false): return 1
        case (.right, true), (.left, false): return 2
        case (.left, true), (.right, false): return 3
        }
    }

    static func fraction(_ offset: Int) -> Double {
        let value = Double(offset) / 65535
        for target in [0.0, 0.5, 1.0] where abs(value - target) <= AnchorCapture.snapTolerance { return target }
        return value
    }

    private static func offset(_ fraction: Double) -> Int {
        let raw = Int((fraction * 65535).rounded())
        return min(max(raw, 0), 65535)
    }

    /// The local device is the device whose newest record pairs one of its
    /// own displays with a display in `localDisplayUUIDs` (R3). Scans every
    /// link in every heap entry, not just the head. Ties broken by the
    /// lexicographically smallest device id, for a deterministic result —
    /// `Dictionary.max` does not guarantee one on a tie.
    static func localDeviceID(in log: UniversalControlLog, localDisplayUUIDs: Set<String>) -> String? {
        var newestByDevice: [String: Int64] = [:]
        for link in log.entries.flatMap(\.links) {
            if localDisplayUUIDs.contains(link.displayA) {
                newestByDevice[link.deviceA] = max(newestByDevice[link.deviceA] ?? .min, link.timestamp)
            }
            if localDisplayUUIDs.contains(link.displayB) {
                newestByDevice[link.deviceB] = max(newestByDevice[link.deviceB] ?? .min, link.timestamp)
            }
        }
        return newestByDevice
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .first?.key
    }

    static func readLog(_ url: URL) throws(RemoteScreenError) -> UniversalControlLog {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RemoteScreenError.unreadable("\(url.lastPathComponent): cannot read")
        }
        guard let outer = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let configuration = outer["Configuration"] as? Data
        else { throw RemoteScreenError.unreadable("\(url.lastPathComponent): no Configuration") }
        do {
            return try UniversalControlLog(configuration: configuration)
        } catch let error as RemoteScreenError {
            throw error
        } catch {
            throw RemoteScreenError.unreadable("\(url.lastPathComponent): \(error)")
        }
    }

    private static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }
}
