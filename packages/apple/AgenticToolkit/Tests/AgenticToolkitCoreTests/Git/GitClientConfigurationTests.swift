import Foundation
import Testing
@testable import AgenticToolkitCore

@Suite("GitClientConfiguration", .serialized)
struct GitClientConfigurationTests {

    private let suiteName = "AgenticToolkitGitClientConfigurationTests"

    /// Points `UserSettings.shared` at a fresh, isolated `UserDefaults` domain.
    /// Returns the domain and the closure that puts `UserSettings.shared` back
    /// the way it was found. **Both halves matter**: `UserSettings.shared` is a
    /// process-wide `static var`, so a test that only wipes its own defaults
    /// domain still leaves every later test in the bundle pointed at a
    /// `UserSettings` whose backing store has just been deleted — a failure
    /// that lands somewhere else and looks like anything but this file.
    /// Mirrors `LegacyThemePersistenceTests.freshDefaults()`; not shared with
    /// it because doing so would mean adding a new shared test-support file
    /// for one nine-line helper.
    @MainActor
    private func freshDefaults() -> (defaults: UserDefaults, restore: () -> Void) {
        let previousShared = UserSettings.shared

        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let suiteName = self.suiteName
        return (defaults, {
            UserSettings.shared = previousShared
            defaults.removePersistentDomain(forName: suiteName)
        })
    }

    @Test("defaults match the shipped git")
    func defaults() {
        let configuration = GitClientConfiguration.default
        #expect(configuration.executableURL == URL(fileURLWithPath: "/usr/bin/git"))
        #expect(configuration.timeout == 5)
        #expect(configuration.submoduleHandling == .ignore)
    }

    @Test("fromSettings reads the three git settings")
    @MainActor
    func fromSettings() {
        let (defaults, restore) = freshDefaults()
        defer { restore() }
        UserSettings.shared = UserSettings(with: UserDefaultsSettingsStorageProvider(defaults: defaults))

        UserSettings.gitExecutablePath.value = "/opt/homebrew/bin/git"
        UserSettings.gitStatusTimeoutSeconds.value = 12
        UserSettings.gitStatusIncludesSubmodules.value = true

        let configuration = GitClientConfiguration.fromSettings()
        #expect(configuration.executableURL == URL(fileURLWithPath: "/opt/homebrew/bin/git"))
        #expect(configuration.timeout == 12)
        #expect(configuration.submoduleHandling == .include)
    }

    @Test("a zero timeout setting clamps to 1")
    @MainActor
    func timeoutClampsZeroToOne() {
        let (defaults, restore) = freshDefaults()
        defer { restore() }
        UserSettings.shared = UserSettings(with: UserDefaultsSettingsStorageProvider(defaults: defaults))

        UserSettings.gitStatusTimeoutSeconds.value = 0

        #expect(GitClientConfiguration.fromSettings().timeout == 1)
    }

    @Test("a negative timeout setting clamps to 1")
    @MainActor
    func timeoutClampsNegativeToOne() {
        let (defaults, restore) = freshDefaults()
        defer { restore() }
        UserSettings.shared = UserSettings(with: UserDefaultsSettingsStorageProvider(defaults: defaults))

        UserSettings.gitStatusTimeoutSeconds.value = -5

        #expect(GitClientConfiguration.fromSettings().timeout == 1)
    }
}
