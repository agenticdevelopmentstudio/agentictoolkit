/// Everything the display tools persist, in one versioned file.
public struct DisplayDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public struct Preferences: Codable, Equatable, Sendable {
        public var autoApplyEnabled: Bool
        public init(autoApplyEnabled: Bool = true) { self.autoApplyEnabled = autoApplyEnabled }
    }

    public var version: Int
    public var layouts: [Layout]
    public var labels: [ModeLabelOverride]
    /// Keyed by `DisplayIdentity.key`, newest first.
    public var recentModes: [String: [ModeSpec]]
    public var preferences: Preferences

    public init(layouts: [Layout] = [], labels: [ModeLabelOverride] = [],
                recentModes: [String: [ModeSpec]] = [:], preferences: Preferences = Preferences()) {
        self.version = Self.currentVersion
        self.layouts = layouts
        self.labels = labels
        self.recentModes = recentModes
        self.preferences = preferences
    }

    private enum CodingKeys: String, CodingKey { case version, layouts, labels, recentModes, preferences }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        layouts = try container.decodeIfPresent([Layout].self, forKey: .layouts) ?? []
        labels = try container.decodeIfPresent([ModeLabelOverride].self, forKey: .labels) ?? []
        recentModes = try container.decodeIfPresent([String: [ModeSpec]].self, forKey: .recentModes) ?? [:]
        preferences = try container.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
    }
}
