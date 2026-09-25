#if canImport(AppKit)
import AgenticToolkitHubService
import AgenticToolkitHub
import Foundation

/// The words a script uses for the parts of the shell it can drive, and the
/// parsing that turns each into something the view models already understand.
///
/// It lives in HubKit, next to the controllers the words name, for two
/// reasons. The strings are only meaningful against those controllers — a
/// `field` that is not one of the sign-in screen's three text fields is not a
/// field at all — and parsing is the half of the scripting layer worth
/// testing, while the `NSScriptCommand` subclasses that call it cannot be
/// instantiated from a unit-test bundle with no app host.
public enum HubScripting {

    /// A sign-in text field a script can type into.
    public enum Field: String, CaseIterable, Sendable {
        case email, password, code

        /// Case-insensitive so `Email` and `email` name the same field: a
        /// dictionary reader types what reads well, not what the enum spells.
        public static func parse(_ raw: String) -> Field? {
            Field(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    /// A button on the sign-in screen, named the way the sdef names it.
    ///
    /// Each case maps to a `SignInViewModel` intent, never to a control: a
    /// scripted path that clicked the button would be a second implementation
    /// of what the button does, free to drift from the first.
    public enum Action: Equatable, Sendable {
        case signIn
        case passkey
        case sendCode
        case verify
        case back
        case social(SocialProvider)

        /// `sign-in`, `passkey`, `send-code`, `verify`, `back`, or
        /// `social:<provider>` — the provider being a `SocialProvider` raw
        /// value (`google`, `github`, `gitlab`, `bitbucket`, `apple`).
        public static func parse(_ raw: String) -> Action? {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch text {
            case "sign-in", "signin": return .signIn
            case "passkey": return .passkey
            case "send-code", "sendcode": return .sendCode
            case "verify": return .verify
            case "back": return .back
            default: break
            }
            let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == "social",
                  let provider = SocialProvider(rawValue: String(parts[1]))
            else { return nil }
            return .social(provider)
        }
    }

    /// The slug of the workspace a script named, whether it named the slug or
    /// the label the popup shows.
    ///
    /// Both, because the two are what a script author has in front of them:
    /// the slug is what `ui state` reports and what `selectWorkspace(slug:)`
    /// takes, while the label — `"Name (slug)"` — is what a screenshot shows.
    /// Refusing the label would make the visible name the one string that does
    /// not work.
    public static func workspaceSlug(matching raw: String, in workspaces: [HubWorkspace]) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = workspaces.first(where: { $0.slug == text }) { return exact.slug }
        if let labelled = workspaces.first(where: { $0.listLabel == text }) { return labelled.slug }
        let folded = text.lowercased()
        return workspaces.first {
            $0.slug.lowercased() == folded || $0.listLabel.lowercased() == folded
        }?.slug
    }
}

extension AccountMenuModel.Item {
    /// The account-menu item a script named.
    ///
    /// `logOut` is the raw value, but a script author reading the dictionary
    /// types what the menu shows and what every other name in this app looks
    /// like — so `log-out` and `logout` name it too. Nothing else does: an
    /// unrecognised word is an error the command reports, not a no-op it
    /// swallows.
    public static func parse(_ raw: String) -> AccountMenuModel.Item? {
        let folded = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch folded {
        case "log-out", "logout": return .logOut
        default:
            return AccountMenuModel.Item.allCases.first { $0.rawValue.lowercased() == folded }
        }
    }
}
#endif
