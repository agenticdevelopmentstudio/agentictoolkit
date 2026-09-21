import Testing
import Foundation
@testable import AgenticToolkitCore

/// The one setting the extension feature stores, and the two facts about it
/// that are not free to change.
///
/// A declaration rather than logic, which is why it had no test — and also
/// why it needs one. Both properties asserted here are *contracts with data
/// already on disk*: the key is what every user's existing choices are filed
/// under, and the default is what decides whether an extension nobody has an
/// opinion about runs. Neither has a compiler or a caller that would notice a
/// change, so a rename made while tidying would ship as a silent reset.
@MainActor
struct ExtensionSettingsTests {

    /// Changing this orphans every user's disabled list — the extensions they
    /// switched off all come back on at the next launch, with nothing in the
    /// UI to say why. The same contract `theme.custom_themes` carries, and the
    /// same reason it is pinned rather than trusted.
    @Test("the disabled-extensions key is the one already on disk")
    func theStorageKeyIsPinned() {
        #expect(UserSettings.disabledExtensionIdentifiers.name
            == "extensions.disabledIdentifiers")
    }

    /// Disabled-rather-than-enabled is the whole design: an extension the user
    /// has never expressed an opinion about runs. Flipping the sense of this
    /// list — or seeding it — would make a fresh install activate nothing at
    /// all, which looks exactly like an extension host that failed to start.
    @Test("nothing is disabled until the user says so")
    func nothingIsDisabledByDefault() {
        #expect(UserSettings.disabledExtensionIdentifiers.defaultValue.isEmpty)
    }
}
