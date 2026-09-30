import CoreGraphics

/// What `LayoutService.apply(_:)` would do, computed by `plan(_:)` without touching hardware.
public struct ApplyPlan: Equatable, Sendable {
    public let modeChanges: [CGDirectDisplayID: ModeSpec]
    public let origins: [CGDirectDisplayID: CGPoint]
    public let originsChanged: Bool
    public let remoteChanges: [RemoteScreenID: Anchor]

    public init(
        modeChanges: [CGDirectDisplayID: ModeSpec], origins: [CGDirectDisplayID: CGPoint],
        originsChanged: Bool, remoteChanges: [RemoteScreenID: Anchor]
    ) {
        self.modeChanges = modeChanges
        self.origins = origins
        self.originsChanged = originsChanged
        self.remoteChanges = remoteChanges
    }

    public var isNoOp: Bool { modeChanges.isEmpty && !originsChanged && remoteChanges.isEmpty }
}

/// Outcome of writing remote (Universal Control) placements during an apply.
public enum RemoteApplyResult: Equatable, Sendable {
    case none
    case applied(Int)
    case unsupported(String)
    case failed(RemoteScreenError)
}

/// What `LayoutService.apply(_:)` actually did.
public struct ApplyReport: Equatable, Sendable {
    public let changedModes: [CGDirectDisplayID]
    public let arranged: Bool
    public let drift: [ArrangeDrift]
    public let remote: RemoteApplyResult
    /// Set when the modes were applied but recording them as recent modes
    /// failed. The hardware change stands; only the recents list is stale.
    public let recentsError: LayoutServiceError?

    public init(
        changedModes: [CGDirectDisplayID], arranged: Bool, drift: [ArrangeDrift],
        remote: RemoteApplyResult, recentsError: LayoutServiceError? = nil
    ) {
        self.changedModes = changedModes
        self.arranged = arranged
        self.drift = drift
        self.remote = remote
        self.recentsError = recentsError
    }
}
