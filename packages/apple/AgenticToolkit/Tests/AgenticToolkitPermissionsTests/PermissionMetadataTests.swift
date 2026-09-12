import Foundation
import Testing
@testable import AgenticToolkitPermissions

@Suite("Permission metadata")
struct PermissionMetadataTests {
    private static let allKinds: [Permission] = [
        .accessibility,
        .notifications,
        .automation(targetBundleID: "com.googlecode.iterm2"),
        .location,
        .microphone,
        .screenCapture,
        .keychain(service: "Claude Code-credentials")
    ]

    @Test("display names")
    func displayNames() {
        #expect(Permission.accessibility.displayName == "Accessibility")
        #expect(Permission.notifications.displayName == "Notifications")
        #expect(Permission.automation(targetBundleID: "com.googlecode.iterm2").displayName == "Automation")
        // Exact string match matters here beyond cosmetics: MacPermissionGateTests'
        // ScriptedChecker (in the OlyloCore superproject) keys its answers by
        // this displayName, so a drift here would silently answer .undetermined
        // for every location query there.
        #expect(Permission.location.displayName == "Location")
        #expect(Permission.keychain(service: "Claude Code-credentials").displayName == "Keychain")
        #expect(Permission.microphone.displayName == "Microphone")
        #expect(Permission.screenCapture.displayName == "Screen Capture")
    }

    @Test("each keychain service is its own identifier and its own explanation")
    func keychainServicesAreDistinct() {
        let live = Permission.keychain(service: "Claude Code-credentials")
        let saved = Permission.keychain(service: "Stenographer Claude Accounts")
        #expect(live.identifierToken == "keychain-claude-code-credentials")
        #expect(saved.identifierToken == "keychain-stenographer-claude-accounts")
        #expect(live.explanation != saved.explanation)
        #expect(live.explanation.contains("Claude Code-credentials"))
    }

    @Test("every permission has a non-empty SF Symbol and explanation")
    func symbolsAndExplanations() {
        for permission in Self.allKinds {
            #expect(!permission.systemImageName.isEmpty)
            #expect(!permission.explanation.isEmpty)
        }
    }

    @Test("settings pane URLs point at the right panes")
    func settingsPaneURLs() {
        #expect(
            Permission.accessibility.settingsPaneURL?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        #expect(
            Permission.automation(targetBundleID: "com.googlecode.iterm2").settingsPaneURL?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        )
        #expect(
            Permission.notifications.settingsPaneURL?.absoluteString
                .hasPrefix("x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=") == true
        )
        #expect(
            Permission.location.settingsPaneURL?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        )
        #expect(
            Permission.microphone.settingsPaneURL?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
        #expect(
            Permission.screenCapture.settingsPaneURL?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    @Test("a keychain permission has no settings pane, and its button says so")
    func keychainHasNoSettingsPane() {
        // Not an oversight: Keychain access is not a TCC permission, so System
        // Settings lists no pane for it and the grant happens in the dialog the
        // app's own read raises.
        #expect(Permission.keychain(service: "Claude Code-credentials").settingsPaneURL == nil)
        #expect(Permission.keychain(service: "Claude Code-credentials").actionTitle == "Allow\u{2026}")
        #expect(Permission.accessibility.actionTitle == "Open Settings")
    }
}
