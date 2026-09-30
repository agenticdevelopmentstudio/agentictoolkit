/// Most-recently-used modes per display, newest first, distinct, at most `limit`.
public enum RecentModes {
    public static let limit = 3

    public static func recording(_ spec: ModeSpec, in list: [ModeSpec]) -> [ModeSpec] {
        Array(([spec] + list.filter { !$0.matches(spec) }).prefix(limit))
    }
}
