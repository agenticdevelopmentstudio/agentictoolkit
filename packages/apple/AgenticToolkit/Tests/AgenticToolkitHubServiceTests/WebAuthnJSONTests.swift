import OpenAPIRuntime
import XCTest
@testable import AgenticToolkitHubService

final class WebAuthnJSONTests: XCTestCase {
    func testBase64URLRoundTrip() {
        let data = Data([0xfb, 0xff, 0x00, 0x7e, 0x3f])
        let encoded = WebAuthnJSON.base64URLEncode(data)
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertEqual(WebAuthnJSON.base64URLDecode(encoded), data)
        XCTAssertEqual(WebAuthnJSON.base64URLDecode("AQID"), Data([1, 2, 3]))
        XCTAssertNil(WebAuthnJSON.base64URLDecode("***"))
    }

    func testParsesTopLevelRequestOptions() throws {
        let options = try OpenAPIObjectContainer(unvalidatedValue: [
            "challenge": "AQID",
            "rpId": "agenticdeveloperhub.com",
            "allowCredentials": [["id": "BAU", "type": "public-key"]],
            "userVerification": "preferred"
        ])
        let request = try WebAuthnJSON.assertionRequest(from: options)
        XCTAssertEqual(request.challenge, Data([1, 2, 3]))
        XCTAssertEqual(request.rpID, "agenticdeveloperhub.com")
        XCTAssertEqual(request.allowedCredentialIDs, [Data([4, 5])])
    }

    func testParsesOptionsNestedUnderPublicKey() throws {
        let options = try OpenAPIObjectContainer(unvalidatedValue: [
            "publicKey": ["challenge": "AQID", "rpId": "example.com"]
        ])
        let request = try WebAuthnJSON.assertionRequest(from: options)
        XCTAssertEqual(request.rpID, "example.com")
        XCTAssertEqual(request.allowedCredentialIDs, [])
    }

    func testMissingChallengeFails() throws {
        let options = try OpenAPIObjectContainer(unvalidatedValue: ["rpId": "example.com"])
        XCTAssertThrowsError(try WebAuthnJSON.assertionRequest(from: options)) { error in
            XCTAssertEqual(error as? WebAuthnJSONError, .missingField("challenge"))
        }
    }

    func testAssertionResponseShape() {
        let response = WebAuthnJSON.assertionResponse(
            credentialID: Data([4, 5]),
            clientDataJSON: Data([1]),
            authenticatorData: Data([2]),
            signature: Data([3]),
            userHandle: nil
        )
        XCTAssertEqual(response.value["id"] as? String, "BAU")
        XCTAssertEqual(response.value["rawId"] as? String, "BAU")
        XCTAssertEqual(response.value["type"] as? String, "public-key")
        let inner = response.value["response"] as? [String: (any Sendable)?]
        XCTAssertEqual(inner?["clientDataJSON"] as? String, "AQ")
        XCTAssertEqual(inner?["authenticatorData"] as? String, "Ag")
        XCTAssertEqual(inner?["signature"] as? String, "Aw")
        XCTAssertNil(inner?["userHandle"] ?? nil)
    }
}
