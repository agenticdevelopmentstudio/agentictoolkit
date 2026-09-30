import Foundation

/// Named `DisplayPlacement` rather than `Placement`: `web-features` already
/// exports an unrelated `Placement` (a web package's placement type), so this
/// tier cannot reuse that name.
public struct DisplayPlacement: Hashable, Codable, Sendable {
    public var display: DisplayRef
    /// Nil only for the main display.
    public var anchor: Anchor?
    /// Mode to set when the layout's `applyModes` is on.
    public var mode: ModeSpec?

    public init(display: DisplayRef, anchor: Anchor?, mode: ModeSpec?) {
        self.display = display
        self.anchor = anchor
        self.mode = mode
    }
}

/// A named, anchor-based arrangement for one set of displays.
public struct Layout: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    /// `DisplaySet.id` of the local displays this layout was made for.
    public var displaySetID: String
    public var main: DisplayIdentity
    public var placements: [DisplayPlacement]
    public var applyModes: Bool
    public var autoApply: Bool

    public init(id: UUID = UUID(), name: String, displaySetID: String, main: DisplayIdentity,
                placements: [DisplayPlacement], applyModes: Bool = false, autoApply: Bool = false) {
        self.id = id
        self.name = name
        self.displaySetID = displaySetID
        self.main = main
        self.placements = placements
        self.applyModes = applyModes
        self.autoApply = autoApply
    }

    public var localAnchors: [DisplayIdentity: Anchor] {
        var result: [DisplayIdentity: Anchor] = [:]
        for placement in placements {
            if case let .local(identity) = placement.display, let anchor = placement.anchor {
                result[identity] = anchor
            }
        }
        return result
    }

    public var remoteAnchors: [RemoteScreenID: Anchor] {
        var result: [RemoteScreenID: Anchor] = [:]
        for placement in placements {
            if case let .remote(id) = placement.display, let anchor = placement.anchor { result[id] = anchor }
        }
        return result
    }

    public func mode(for identity: DisplayIdentity) -> ModeSpec? {
        placements.first { $0.display == .local(identity) }?.mode
    }
}
