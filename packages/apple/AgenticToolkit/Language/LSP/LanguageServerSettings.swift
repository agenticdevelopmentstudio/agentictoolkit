//
//  LanguageServerSettings.swift
//  AgenticToolkit
//

import AgenticToolkitCore
import Foundation

@MainActor
extension UserSettings {

    /// Non-secret language-server descriptions. Routed to the regular settings
    /// provider.
    ///
    /// **The key name and its JSON encoding are load-bearing once shipped:**
    /// they are what a user's configured servers are stored under, and changing
    /// either orphans them silently — the same contract `theme.custom_themes`
    /// carries.
    public static let languageServerConfigurations = UserSetting<[LanguageServerConfiguration]>(
        "languageServer.serverConfigurations",
        default: []
    )

    /// Secret environment values for configured servers. Routed to the secure
    /// provider (Keychain in production) via `isSecure: true`, so tokens never
    /// land in the regular settings file. Keyed by
    /// `LanguageServerConfiguration.id.uuidString`, then by environment-variable
    /// name.
    public static let languageServerSecrets = UserSetting<LanguageServerSecrets>(
        "languageServer.serverSecrets",
        default: [:],
        isSecure: true
    )
}
