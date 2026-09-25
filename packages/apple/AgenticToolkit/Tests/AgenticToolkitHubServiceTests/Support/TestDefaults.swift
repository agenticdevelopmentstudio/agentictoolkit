import Foundation

/// A throwaway `UserDefaults` suite. Tests must never touch `.standard`:
/// `hub.recents`, `hub.cachedUser` and `useDirectMode` are real app state.
struct IsolatedDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = "HubKitTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("could not create UserDefaults suite \(suiteName)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        self.defaults = defaults
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
