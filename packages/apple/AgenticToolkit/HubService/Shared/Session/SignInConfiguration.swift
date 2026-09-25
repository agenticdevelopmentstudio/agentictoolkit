import AgenticDeveloperHubClient
import Foundation

/// Spec §5.2 social providers, in the order the sign-in screen lists them.
public enum SocialProvider: String, CaseIterable, Sendable {
    case google, github, gitlab, bitbucket, apple

    public var label: String {
        switch self {
        case .google: "Google"
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .bitbucket: "Bitbucket"
        case .apple: "Apple"
        }
    }
}

/// Where sign-in goes and how the browser comes back (spec §5.2).
///
/// The shape of "comes back" is dictated by the backend, and it is not the one
/// a native app would pick for itself. Two of its rules decide everything here:
///
/// 1. `/oauth/signin/start` refuses any `return` that is not `http(s)://`
///    (`isValidReturnUrl` in `routes/oauthRedirect.ts`), so a custom-scheme
///    callback — `adh://auth-callback`, what `ASWebAuthenticationSession` would
///    normally be handed — is rejected with `invalid return URL` before the
///    client is even looked up.
/// 2. The exchange code the callback carries is bound to the `User-Agent` of
///    whoever received it (`OAuthExchangeStore.consume`), which is the browser.
///
/// So the app returns to a **loopback listener it runs itself** (RFC 8252's
/// native-app pattern, and exactly what the `adh` CLI already does), and
/// redeems the code with the browser's own `User-Agent` forwarded — see
/// `LoopbackAuthServer`. The custom scheme survives in one much smaller role:
/// the capture page's last hop is `adh://auth-callback`, which is how
/// `ASWebAuthenticationSession` learns the flow is over and dismisses itself.
public struct SignInConfiguration: Sendable, Equatable {
    public static let bundleClientIDKey = "ADHSignInClientId"
    public static let environmentClientIDKey = "HUB_SIGNIN_CLIENT_ID"

    /// The backend has no `hub` client — `clientId=hub` 400s with
    /// `client not found` on every environment. `adh-cli` is the one built-in
    /// client whose allow-listed return origins are loopback
    /// (`ADH_CLI_RETURN_ORIGINS` in `auth/oauth/clients.ts`, seeded in every
    /// env including production), which is what a native app needs. The apps
    /// therefore sign in as it until a dedicated client is provisioned; when
    /// one is, it needs no code change — set `ADHSignInClientId` in the app's
    /// Info.plist (or `HUB_SIGNIN_CLIENT_ID` in the environment) and give it
    /// the same loopback origins.
    public static let defaultClientID = "adh-cli"

    /// The loopback ports the backend allow-lists for that client, in the
    /// order they are tried. These are not ours to choose: `originAllowed`
    /// matches an exact origin, so a port outside this set is refused with
    /// `return URL origin not allowed for this client`. Keep in step with
    /// `ADH_CLI_RETURN_ORIGINS`.
    public static let loopbackPorts: [UInt16] = [8517, 8518, 8519]

    public let clientID: String
    public let callbackScheme: String
    public let backendURL: URL

    public init(clientID: String, callbackScheme: String = "adh", backendURL: URL = DaemonContract.backendURL) {
        self.clientID = clientID
        self.callbackScheme = callbackScheme
        self.backendURL = backendURL
    }

    /// `adh://auth-callback` — registered in both Info.plists (Task 2). No
    /// longer an OAuth `return` (the backend refuses custom schemes); it is
    /// the URL the capture page navigates to once it has handed the code to
    /// the loopback listener, so that `ASWebAuthenticationSession` — which
    /// intercepts exactly this scheme — closes the browser sheet.
    public var callbackURL: URL {
        guard let url = URL(string: "\(callbackScheme)://auth-callback") else {
            preconditionFailure("invalid callback scheme \(callbackScheme)")
        }
        return url
    }

    /// Environment override first (developers pointing at a dev client),
    /// then the Info.plist value, then ``defaultClientID``.
    public static func fromBundle(
        _ bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SignInConfiguration {
        if let fromEnv = environment[environmentClientIDKey], !fromEnv.isEmpty {
            return SignInConfiguration(clientID: fromEnv)
        }
        if let fromPlist = bundle.object(forInfoDictionaryKey: bundleClientIDKey) as? String, !fromPlist.isEmpty {
            return SignInConfiguration(clientID: fromPlist)
        }
        return SignInConfiguration(clientID: defaultClientID)
    }

    /// `{backend}/oauth/signin/start?clientId=…&providerId=…&return={returnURL}`
    /// — the same start endpoint the web app and the `adh` CLI use; the
    /// backend redirects the browser back to `returnURL` with `#code=<code>`
    /// (spec §5.2).
    ///
    /// No `state`/nonce parameter is sent: the documented query contract for
    /// this endpoint is exactly `clientId`/`providerId`/`return` (confirmed by
    /// the generated Swift and Python clients and by the web app's own
    /// `buildAuthorizeUrl`), and it is not echoed back — the only
    /// client-supplied token the backend round-trips is `linkNonce`, scoped to
    /// `link=1` account-linking. Adding one here would validate against a
    /// field the server silently drops.
    ///
    /// What stands in for it is the nonce `returnURL` carries. It is minted
    /// per attempt, known only to this process and the browser the backend
    /// redirects, and both listener routes refuse a request without it — so a
    /// code can only reach this app through the attempt that asked for it,
    /// even though another local process may bind the port on the next run.
    public func socialStartURL(provider: SocialProvider, returnURL: URL) -> URL {
        var components = URLComponents(url: backendURL, resolvingAgainstBaseURL: false)
        components?.path = "/oauth/signin/start"
        components?.queryItems = [
            URLQueryItem(name: "clientId", value: clientID),
            URLQueryItem(name: "providerId", value: provider.rawValue),
            URLQueryItem(name: "return", value: returnURL.absoluteString)
        ]
        guard let url = components?.url else {
            preconditionFailure("could not build social start URL from \(backendURL)")
        }
        return url
    }
}
