import Foundation

/// The last known signed-in user (spec §5.1): shown while `/auth/me` is
/// unreachable so a cold offline launch still lands in the workspace.
///
/// Not `Sendable`: this SDK marks `UserDefaults`'s `Sendable` conformance
/// unavailable (`@_nonSendable(_assumed)`), so claiming one here would need
/// an unchecked escape hatch this codebase forbids. Every real caller is
/// either `@MainActor`-isolated (`SessionController`, SE-0316: a global
/// actor class's stored properties need not themselves be `Sendable`) or a
/// synchronous, non-crossing call site (tests), so no actual concurrency
/// hazard exists — only the blanket compiler proof is unavailable.
public struct CachedUserStore {
    public static let key = "hub.cachedUser"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> HubUser? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(HubUser.self, from: data)
    }

    public func save(_ user: HubUser) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
