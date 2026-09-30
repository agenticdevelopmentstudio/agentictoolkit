import CoreGraphics

public struct ArrangeDrift: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let requested: CGPoint
    public let actual: CGPoint

    public init(displayID: CGDirectDisplayID, requested: CGPoint, actual: CGPoint) {
        self.displayID = displayID
        self.requested = requested
        self.actual = actual
    }
}

/// Mode changes and arrangement, each as one permanent transaction.
@MainActor
public struct DisplayConfigurator {
    public let system: DisplaySystem

    public init(system: DisplaySystem) { self.system = system }

    /// The display's mode matching `spec`, preferring GUI-usable modes.
    public func resolve(_ spec: ModeSpec, for displayID: CGDirectDisplayID) throws -> DisplayMode {
        let candidates = system.modes(for: displayID).filter { $0.spec.matches(spec) }
        guard let mode = candidates.first(where: \.isUsableForDesktopGUI) ?? candidates.first else {
            throw DisplayError.modeNotAvailable(spec)
        }
        return mode
    }

    @discardableResult
    public func setMode(_ spec: ModeSpec, for displayID: CGDirectDisplayID) throws -> DisplayMode {
        guard system.onlineDisplays().contains(where: { $0.id == displayID }) else {
            throw DisplayError.displayNotFound(displayID)
        }
        let mode = try resolve(spec, for: displayID)
        try system.apply([.mode(displayID, mode)])
        return mode
    }

    /// Moves displays in one transaction. Exactly one display must be placed
    /// at (0,0); it becomes main. Returns where macOS put a display somewhere
    /// other than requested.
    public func arrange(origins: [CGDirectDisplayID: CGPoint]) throws -> [ArrangeDrift] {
        guard origins.values.filter({ $0 == .zero }).count == 1 else { throw DisplayError.noMainOrigin }
        let known = Set(system.onlineDisplays().map(\.id))
        if let unknown = origins.keys.sorted().first(where: { !known.contains($0) }) {
            throw DisplayError.displayNotFound(unknown)
        }
        let sortedOrigins = origins.sorted { $0.key < $1.key }
        let changes = sortedOrigins.map { DisplayConfigurationChange.origin($0.key, $0.value) }
        try system.apply(changes)
        let actual = Dictionary(uniqueKeysWithValues: system.onlineDisplays().map { ($0.id, $0.bounds.origin) })
        return sortedOrigins.compactMap { id, requested in
            guard let now = actual[id], now != requested else { return nil }
            return ArrangeDrift(displayID: id, requested: requested, actual: now)
        }
    }
}
