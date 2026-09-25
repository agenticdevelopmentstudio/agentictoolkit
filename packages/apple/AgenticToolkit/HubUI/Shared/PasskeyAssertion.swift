import AgenticToolkitHubService
import AgenticDeveloperHubClient
import AuthenticationServices
import Foundation
import OpenAPIRuntime

/// `PasskeyAssertionProvider` backed by `ASAuthorizationController`.
/// Requires the app's associated-domains entitlement (`webcredentials:`) and
/// a provisioning profile to succeed on a real device; without them the
/// system sheet fails and the error surfaces as a normal sign-in error.
public struct PasskeyAssertion: PasskeyAssertionProvider {
    public init() {}

    public func assert(options: OpenAPIObjectContainer) async throws -> OpenAPIObjectContainer {
        let request = try WebAuthnJSON.assertionRequest(from: options)
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: request.rpID)
        let assertionRequest = provider.createCredentialAssertionRequest(challenge: request.challenge)
        assertionRequest.allowedCredentials = request.allowedCredentialIDs.map {
            ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
        }
        let credential = try await PasskeyAuthorizationRunner().run(assertionRequest)
        return WebAuthnJSON.assertionResponse(
            credentialID: credential.credentialID,
            clientDataJSON: credential.rawClientDataJSON,
            authenticatorData: credential.rawAuthenticatorData,
            signature: credential.signature,
            userHandle: credential.userID
        )
    }
}

/// Bridges the delegate-based `ASAuthorizationController` to async/await.
/// The controller retains its delegate only for the duration of a request,
/// so the runner keeps itself alive until the continuation resumes.
@MainActor
private final class PasskeyAuthorizationRunner: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationPlatformPublicKeyCredentialAssertion, any Error>?
    private var retained: PasskeyAuthorizationRunner?

    func run(
        _ request: ASAuthorizationPlatformPublicKeyCredentialAssertionRequest
    ) async throws -> ASAuthorizationPlatformPublicKeyCredentialAssertion {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.retained = self
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { finish() }
        guard let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            continuation?.resume(throwing: SessionError.unexpectedResponse("Unexpected credential type"))
            return
        }
        continuation?.resume(returning: assertion)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        defer { finish() }
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation?.resume(throwing: CancellationError())
        } else {
            continuation?.resume(throwing: error)
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        PresentationAnchors.current()
    }

    private func finish() {
        continuation = nil
        retained = nil
    }
}
