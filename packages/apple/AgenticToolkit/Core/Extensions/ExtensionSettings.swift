//
//  ExtensionSettings.swift
//  AgenticToolkit
//

import Foundation

@MainActor
extension UserSettings {

    /// Identifiers the user has switched off. Disabled rather than enabled,
    /// so a freshly installed extension is on by default and no migration is
    /// needed when one is added.
    ///
    /// **The key string is load-bearing.** Changing it orphans every user's
    /// choices and needs a migration — the same contract `theme.custom_themes`
    /// carries.
    public static let disabledExtensionIdentifiers = UserSetting<Set<String>>(
        "extensions.disabledIdentifiers",
        default: []
    )
}
