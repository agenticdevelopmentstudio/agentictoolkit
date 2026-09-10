import Foundation
import Testing
@testable import AgenticToolkitCore

@Suite("GitClientConfiguration", .serialized)
struct GitClientConfigurationTests {
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
        let previousPath = UserSettings.gitExecutablePath.value
        let previousTimeout = UserSettings.gitStatusTimeoutSeconds.value
        let previousSubmodules = UserSettings.gitStatusIncludesSubmodules.value
        defer {
            UserSettings.gitExecutablePath.value = previousPath
            UserSettings.gitStatusTimeoutSeconds.value = previousTimeout
            UserSettings.gitStatusIncludesSubmodules.value = previousSubmodules
        }
        UserSettings.gitExecutablePath.value = "/opt/homebrew/bin/git"
        UserSettings.gitStatusTimeoutSeconds.value = 12
        UserSettings.gitStatusIncludesSubmodules.value = true

        let configuration = GitClientConfiguration.fromSettings()
        #expect(configuration.executableURL == URL(fileURLWithPath: "/opt/homebrew/bin/git"))
        #expect(configuration.timeout == 12)
        #expect(configuration.submoduleHandling == .include)
    }
}
