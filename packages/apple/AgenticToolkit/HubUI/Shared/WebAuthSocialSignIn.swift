import AgenticToolkitHubService
import AgenticDeveloperHubClient
import AuthenticationServices
import Foundation

/// `SocialSignInProvider` built from the two halves the backend forces apart:
/// `ASWebAuthenticationSession` drives the browser, and a
/// ``LoopbackAuthServer`` catches the code on its way back.
///
/// The browser session is still what *runs* the flow — it owns the sheet, the
/// shared cookie jar, and the user's ability to cancel — but it is no longer
/// what delivers the result. It cannot be: the backend refuses a
/// custom-scheme `return`, and the code it mints is redeemable only by the
/// browser's own `User-Agent` (both documented on ``SignInConfiguration``).
/// So the session's callback scheme survives purely as the signal that the
/// flow is over, and the code arrives over loopback instead.
///
/// The two races the pairing creates are both resolved by
/// ``LoopbackAuthServer``'s one-shot outcome: a delivery that lands before the
/// browser closes wins, and a browser that closes before any delivery becomes
/// a cancellation.
public struct WebAuthSocialSignIn: SocialSignInProvider {
    public init() {}

    public func authenticate(_ request: SocialSignInRequest) async throws -> SocialSignInResult {
        let server = try await LoopbackAuthServer.bind(dismissURL: request.dismissURL)
        let runner = await WebAuthRunner()
        let startURL = request.makeStartURL(server.returnURL)

        // The browser runs alongside the wait rather than before it, because
        // the code arrives at the listener *while* the session is still open —
        // the session only ends afterwards, when the capture page takes its
        // last hop to the callback scheme.
        let browser = Task {
            do {
                try await runner.run(startURL: startURL, callbackScheme: request.callbackScheme)
                // The callback scheme fired. Either a delivery already landed
                // (this is then a no-op) or the user got out some other way.
                server.abort()
            } catch is CancellationError {
                server.abort()
            } catch {
                server.fail(error)
            }
        }

        let outcome: Result<SocialSignInResult, any Error>
        do {
            outcome = .success(try await server.waitForDelivery())
        } catch {
            outcome = .failure(error)
        }
        // Dismiss the sheet ourselves on success: the capture page's hop to
        // the callback scheme would do it a beat later, but the user has
        // nothing left to read.
        await runner.cancel()
        browser.cancel()
        server.shutdown()
        return try outcome.get()
    }
}

@MainActor
final class WebAuthRunner: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var retained: WebAuthRunner?

    /// Returns when the browser session ends — normally because the capture
    /// page navigated to the callback scheme. The URL it ends on is
    /// deliberately discarded: it carries no code (see
    /// ``LoopbackAuthServer``), only the fact that the flow finished.
    func run(startURL: URL, callbackScheme: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            // What binds this callback to the attempt that started it is the
            // per-attempt nonce in the loopback `return` URL, not an OAuth
            // `state`: `/oauth/signin/start` accepts only `clientId`,
            // `providerId` and `return`, and round-trips no opaque token, so
            // a `state` could not be validated even if one were sent. The
            // nonce is equivalent in effect and is checked where it matters —
            // on the listener, which refuses any request without it.
            //
            // The app still registers no URL-open handler for the callback
            // scheme, so the only way this session can end is the system
            // handing the URL back to the session that started it.
            let session = ASWebAuthenticationSession(
                url: startURL,
                callbackURLScheme: callbackScheme,
                completionHandler: completionHandler(resuming: continuation)
            )
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            self.retained = self
            // `ASWebAuthenticationSession.start()` returns `false` when the
            // session could not be started at all (no presentation context,
            // already started, or previously cancelled) — and Apple documents
            // that in that case the completion handler above is *never*
            // invoked (ASWebAuthenticationSession.h:94-99). Without this
            // guard, `false` would leave the continuation unresumed forever:
            // `signInWithSocial` would never return, `isBusy` would stay
            // `true`, and every button on the sign-in screen would render
            // permanently disabled with no error shown. Resume here ourselves
            // and run the same cleanup the completion handler runs elsewhere.
            guard session.start() else {
                finish()
                continuation.resume(throwing: SessionError.unexpectedResponse(
                    "Could not open the sign-in window. Please try again."
                ))
                return
            }
        }
    }

    /// The session's completion handler, built here rather than inline so a
    /// test can call it from the queue the system actually calls it from.
    ///
    /// `ASWebAuthenticationSession` invokes its handler on the XPC queue that
    /// carries Safari's reply (`com.apple.NSXPCConnection.m-user.com.apple
    /// .SafariLaunchAgent`), never on the main thread. A closure written
    /// inline in ``run(startURL:callbackScheme:)`` inherits this class's
    /// `@MainActor` isolation, which compiles and then traps the instant the
    /// sheet closes: Swift 6 checks that isolation at runtime, and
    /// `dispatch_assert_queue` fails. So this is `nonisolated`, returns a
    /// `@Sendable` closure, and hops to the main actor itself.
    nonisolated func completionHandler(
        resuming continuation: CheckedContinuation<Void, any Error>
    ) -> @Sendable (URL?, (any Error)?) -> Void {
        { [weak self] _, error in
            // The callback URL is deliberately discarded — it carries no
            // code, only the fact that the flow finished.
            Task { @MainActor in
                self?.finish()
                guard let error else {
                    continuation.resume()
                    return
                }
                if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Dismisses the sheet if it is still up. The completion handler fires
    /// with `.canceledLogin`, which the caller reads as "the browser ended" —
    /// harmless once a code has already been delivered.
    func cancel() {
        session?.cancel()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        PresentationAnchors.current()
    }

    private func finish() {
        session = nil
        retained = nil
    }
}

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// The window both system sheets attach to.
@MainActor
enum PresentationAnchors {
    static func current() -> ASPresentationAnchor {
        #if canImport(AppKit)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let anyWindow = scenes.first?.windows.first {
            return anyWindow
        }
        // `ASPresentationAnchor()` (bare `UIWindow.init()`) is deprecated in
        // favor of `init(windowScene:)`; there is no scene-less fallback to
        // construct, so a running app with no connected `UIWindowScene` at
        // all is an invalid-state we fail fast on rather than paper over.
        guard let scene = scenes.first else {
            preconditionFailure("PresentationAnchors.current(): no connected UIWindowScene")
        }
        return UIWindow(windowScene: scene)
        #endif
    }
}
