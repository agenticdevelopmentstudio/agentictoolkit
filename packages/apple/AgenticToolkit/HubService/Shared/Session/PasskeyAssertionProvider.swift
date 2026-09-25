import OpenAPIRuntime

/// Turns the backend's assertion options into a signed assertion. The real
/// implementation (`PasskeyAssertion`, Task 8) drives `ASAuthorizationController`;
/// tests substitute a canned one.
public protocol PasskeyAssertionProvider: Sendable {
    func assert(options: OpenAPIObjectContainer) async throws -> OpenAPIObjectContainer
}
