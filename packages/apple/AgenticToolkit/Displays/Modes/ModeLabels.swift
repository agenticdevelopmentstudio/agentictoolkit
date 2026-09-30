/// A user-chosen name for a mode, keyed by point size (and refresh when set).
public struct ModeLabelOverride: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let refreshRate: Double?
    /// Empty string hides the built-in name.
    public let label: String

    public init(width: Int, height: Int, refreshRate: Double?, label: String) {
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
        self.label = label
    }

    func applies(to spec: ModeSpec) -> Bool {
        guard width == spec.width, height == spec.height else { return false }
        guard let refreshRate else { return true }
        return abs(refreshRate - spec.refreshRate) < 0.5
    }
}

/// Mode names: built-ins plus user overrides. Most specific override wins.
public struct ModeLabels: Equatable, Sendable {
    public static let builtIn: [String: String] = [
        "1280x720": "720p NTSC",
        "1920x1080": "1080p NTSC",
        "2560x1440": "1440p QHD",
        "3840x2160": "4K UHD",
        "5120x2880": "5K",
        "6016x3384": "6K",
        "7680x2160": "Dual 4K UHD",
        "7680x4320": "8K UHD"
    ]

    public private(set) var overrides: [ModeLabelOverride]

    public init(overrides: [ModeLabelOverride] = []) { self.overrides = overrides }

    public func label(for spec: ModeSpec) -> String? {
        let matching = overrides.filter { $0.applies(to: spec) }
        if let chosen = matching.first(where: { $0.refreshRate != nil }) ?? matching.first {
            return chosen.label.isEmpty ? nil : chosen.label
        }
        return Self.builtIn["\(spec.width)x\(spec.height)"]
    }

    /// Sets (or with nil, removes) the override for exactly this key.
    public mutating func set(_ label: String?, width: Int, height: Int, refreshRate: Double?) {
        overrides.removeAll { $0.width == width && $0.height == height && $0.refreshRate == refreshRate }
        if let label {
            overrides.append(ModeLabelOverride(width: width, height: height, refreshRate: refreshRate, label: label))
        }
    }
}
