import AuthenticationServices
import XCTest
import AgenticToolkitHubService
@testable import AgenticToolkitHubUI

/// `WebAuthRunner`'s completion handler shipped isolated to `@MainActor` —
/// which compiles, because the closure was written inline inside a
/// `@MainActor` class, and then traps, because `ASWebAuthenticationSession`
/// invokes it on the XPC queue carrying Safari's reply. Swift 6 checks the
/// isolation at runtime: `dispatch_assert_queue` failed and the app died with
/// `EXC_BREAKPOINT` the instant the sign-in sheet closed.
///
/// Nothing caught it because nothing ever called the handler off the main
/// thread. These tests do exactly that.
final class WebAuthRunnerTests: XCTestCase {

    /// A queue that is emphatically not the main one, standing in for
    /// `com.apple.NSXPCConnection.m-user.com.apple.SafariLaunchAgent`.
    private let systemCallbackQueue = DispatchQueue(label: "test.web-auth-callback")

    private func resume(
        with error: (any Error)?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Result<Void, any Error> {
        let runner = await WebAuthRunner()
        do {
            try await withCheckedThrowingContinuation { continuation in
                let handler = runner.completionHandler(resuming: continuation)
                systemCallbackQueue.async {
                    XCTAssertFalse(
                        Thread.isMainThread,
                        "the test must exercise the off-main path",
                        file: file,
                        line: line
                    )
                    handler(URL(string: "adh://auth-callback"), error)
                }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func testSuccessResumesWhenCalledOffTheMainThread() async {
        guard case .success = await resume(with: nil) else {
            return XCTFail("the handler did not resume cleanly")
        }
    }

    func testCanceledLoginBecomesCancellationWhenCalledOffTheMainThread() async {
        let outcome = await resume(with: ASWebAuthenticationSessionError(.canceledLogin))
        guard case .failure(let error) = outcome else {
            return XCTFail("a cancelled login must not read as success")
        }
        XCTAssertTrue(error is CancellationError)
    }

    func testOtherErrorsArePassedThroughWhenCalledOffTheMainThread() async {
        let failure = ASWebAuthenticationSessionError(.presentationContextInvalid)
        let outcome = await resume(with: failure)
        guard case .failure(let error) = outcome else {
            return XCTFail("a session error must not read as success")
        }
        XCTAssertEqual(
            (error as? ASWebAuthenticationSessionError)?.code,
            .presentationContextInvalid,
            "the real error is what the sign-in screen has to show"
        )
    }
}
