import Foundation
import OpenAPIRuntime

public enum WebAuthnJSONError: Error, Equatable {
    case missingField(String)
}

/// Bridges the backend's WebAuthn JSON (SimpleWebAuthn shapes, base64url
/// fields) and `AuthenticationServices` raw `Data` (spec §5.2 passkeys).
public enum WebAuthnJSON {
    public struct AssertionRequest: Equatable, Sendable {
        public let challenge: Data
        public let rpID: String
        public let allowedCredentialIDs: [Data]

        public init(challenge: Data, rpID: String, allowedCredentialIDs: [Data]) {
            self.challenge = challenge
            self.rpID = rpID
            self.allowedCredentialIDs = allowedCredentialIDs
        }
    }

    public static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    /// Accepts the options object itself or one wrapped in `publicKey`.
    public static func assertionRequest(from options: OpenAPIObjectContainer) throws -> AssertionRequest {
        var fields = options.value
        if let nested = fields["publicKey"] as? [String: (any Sendable)?] {
            fields = nested
        }
        guard let challengeText = fields["challenge"] as? String,
              let challenge = base64URLDecode(challengeText) else {
            throw WebAuthnJSONError.missingField("challenge")
        }
        guard let rpID = fields["rpId"] as? String, !rpID.isEmpty else {
            throw WebAuthnJSONError.missingField("rpId")
        }
        let allowed = (fields["allowCredentials"] as? [(any Sendable)?] ?? [])
            .compactMap { $0 as? [String: (any Sendable)?] }
            .compactMap { $0["id"] as? String }
            .compactMap(base64URLDecode)
        return AssertionRequest(challenge: challenge, rpID: rpID, allowedCredentialIDs: allowed)
    }

    /// The `AuthenticationResponseJSON` shape SimpleWebAuthn verifies.
    public static func assertionResponse(
        credentialID: Data,
        clientDataJSON: Data,
        authenticatorData: Data,
        signature: Data,
        userHandle: Data?
    ) -> OpenAPIObjectContainer {
        let id = base64URLEncode(credentialID)
        let inner: [String: (any Sendable)?] = [
            "clientDataJSON": base64URLEncode(clientDataJSON),
            "authenticatorData": base64URLEncode(authenticatorData),
            "signature": base64URLEncode(signature),
            "userHandle": userHandle.map(base64URLEncode)
        ]
        let payload: [String: (any Sendable)?] = [
            "id": id,
            "rawId": id,
            "type": "public-key",
            "response": inner,
            "clientExtensionResults": [String: (any Sendable)?]()
        ]
        do {
            return try OpenAPIObjectContainer(unvalidatedValue: payload)
        } catch {
            preconditionFailure("assertion payload is made only of strings and dictionaries: \(error)")
        }
    }
}
