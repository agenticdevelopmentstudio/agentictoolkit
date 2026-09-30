import AgenticToolkitCore
import Foundation

/// What `ClaudeAuthStore` needs from the app that hosts it: its settings, and
/// the two things only the app's own processes can do around a switch.
@MainActor
public protocol ClaudeAuthStoreDelegate: AnyObject {

    /// Where the next save goes.
    var saveLocation: ClaudeKeychainLocation { get }

    /// Whether a new machine-wide login is saved without asking.
    var autoSavesLogins: Bool { get }

    /// Runs `body` with every background credential round held off.
    ///
    /// A switch renews the target login, and a round refreshing that same
    /// login meanwhile would spend its refresh token twice. An app with no
    /// such rounds just runs `body`.
    func holdingCredentialRounds(_ body: () async throws -> Void) async throws

    /// Renews `saved` before a switch installs it — proving its refresh token
    /// is alive, and giving `claude` a full-length access token.
    func renewLogin(_ saved: ClaudeOAuthCredential) async -> ClaudeLoginRenewal
}

/// How an attempt to renew a saved login ended — and, for every failure, what
/// the attempt may have done to the saved refresh token.
public enum ClaudeLoginRenewal: Sendable {
    /// The renewer was never reached, so the saved login is exactly as good as
    /// it was.
    case unreached
    /// The request went out and its answer was lost; the refresh token may have
    /// been rotated server-side. `reason` says where it was lost.
    case lost(reason: String)
    /// Renewed: `credential` is the fresh pair, and the saved one is void.
    case refreshed(ClaudeOAuthCredential?)
    /// The saved refresh token was already spent.
    case spent
    /// Anything else. `leftTokenUntouched` is true only when the attempt
    /// certainly did not spend the refresh token.
    case failed(reason: String, leftTokenUntouched: Bool)
}
