import XCTest
import Combine
@testable import AgenticToolkitCore

@MainActor
final class KeychainSecureStorageProviderTests: XCTestCase {
    var serviceID: String!
    var originalService: String!
    var store: KeychainSecureSettingsStorageProvider!
    var cancellables: Set<AnyCancellable>!

    // Tests use unique-per-run service identifiers to isolate from concurrent test runs
    // and from the real bundle's keychain entries.
    override func setUp() async throws {
        try await super.setUp()
        // Capture the global so tearDown can restore it: KeychainHelperTests (same
        // bundle) documents that it relies on the default service, so this suite must
        // not leave its per-run UUID service behind on the shared global.
        originalService = KeychainHelper.service
        serviceID = "KeychainSettingsTests-\(UUID().uuidString)"
        store = KeychainSecureSettingsStorageProvider(service: serviceID)
        cancellables = []
    }

    override func tearDown() async throws {
        // Cancel subscriptions FIRST: otherwise the cleanup removes below re-emit
        // change notifications into a test's still-live sink, fulfilling an already
        // satisfied XCTestExpectation and tripping its over-fulfillment assertion.
        cancellables = nil
        // Best-effort: remove every key our tests touch.
        store.remove(UserSettings.displayName)
        store.remove(UserSettings.userPreferences)
        store.remove(UserSettings.launchCount)
        store.remove(UserSettings.hasCompletedOnboarding)
        store = nil
        // Restore the global service this suite overrode in setUp.
        KeychainHelper.service = originalService
        originalService = nil
        try await super.tearDown()
    }

    // MARK: - Defaults

    func testReturnsDefaultsWhenEmpty() {
        XCTAssertEqual(store.get(UserSettings.displayName), "Anonymous")
        XCTAssertEqual(store.get(UserSettings.launchCount), 0)
    }

    // MARK: - String round-trip (fast path — stored as raw string)

    func testStringRoundTrip() {
        store.set("api-key-12345", for: UserSettings.displayName)
        XCTAssertEqual(store.get(UserSettings.displayName), "api-key-12345")
    }

    func testStringValueIsStoredRawNotJSONQuoted() {
        // The fast path stores Strings without JSON quoting so keychain entries are readable.
        store.set("hello", for: UserSettings.displayName)
        // Read directly via KeychainHelper, bypassing the provider's decoder.
        let raw = KeychainHelper.get(forKey: "test.displayName")
        XCTAssertEqual(raw, "hello")  // not "\"hello\""
    }

    // MARK: - Codable struct

    func testCodableStructRoundTrip() {
        let prefs = UserPreferences(
            displayName: "Brian",
            theme: .dark,
            notificationsEnabled: false
        )
        store.set(prefs, for: UserSettings.userPreferences)
        XCTAssertEqual(store.get(UserSettings.userPreferences), prefs)
    }

    func testCodableStructFallsBackToDefaultOnCorruptedData() {
        // Inject non-JSON garbage under the key.
        KeychainHelper.set("not valid json {{{", forKey: "test.userPreferences")

        let result = store.get(UserSettings.userPreferences)
        XCTAssertEqual(result, UserSettings.userPreferences.defaultValue)
    }

    // MARK: - contains / remove

    func testContainsAndRemove() {
        XCTAssertFalse(store.contains(UserSettings.displayName))
        store.set("secret", for: UserSettings.displayName)
        XCTAssertTrue(store.contains(UserSettings.displayName))

        store.remove(UserSettings.displayName)
        XCTAssertFalse(store.contains(UserSettings.displayName))
        XCTAssertEqual(store.get(UserSettings.displayName), "Anonymous")
    }

    // MARK: - Change notifications

    func testSetEmitsChange() {
        let expectation = expectation(description: "change emitted")
        store.changes
            .sink { key in
                XCTAssertEqual(key, "test.displayName")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        store.set("token", for: UserSettings.displayName)
        wait(for: [expectation], timeout: 1.0)
    }

    func testRemoveEmitsChange() {
        store.set("v", for: UserSettings.displayName)

        let expectation = expectation(description: "remove emits")
        store.changes
            .sink { key in
                XCTAssertEqual(key, "test.displayName")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        store.remove(UserSettings.displayName)
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Read memoization
    //
    // `get` is a synchronous XPC round-trip to securityd, and bulk resolves (every AI
    // configuration's every field, re-run on each daemon reconnect) made it hot enough
    // to pin a core. These cases pin the memo's exact shape by mutating the keychain
    // BEHIND the provider — the one thing a correct memo is allowed to miss — so a
    // future "just read through" regression fails here instead of in Activity Monitor.

    func testRepeatReadsAreServedFromTheMemoNotTheKeychain() {
        store.set("first", for: UserSettings.displayName)
        XCTAssertEqual(store.get(UserSettings.displayName), "first")

        // Delete behind the provider's back. A read-through would now return the
        // default; the memo must still answer "first".
        KeychainHelper.delete(forKey: "test.displayName")
        XCTAssertEqual(store.get(UserSettings.displayName), "first")
    }

    func testAnAbsentKeyIsMemoizedToo() {
        // The costliest read: a miss walks the access-group query, the legacy
        // no-group query, and every retired service. Caching the absence is the
        // whole point, since an unconfigured secret is the common case.
        XCTAssertEqual(store.get(UserSettings.displayName), "Anonymous")

        KeychainHelper.set("written-behind-the-provider", forKey: "test.displayName")
        XCTAssertEqual(store.get(UserSettings.displayName), "Anonymous")
    }

    func testSetRefreshesTheMemo() {
        // Seed the "absent" memo first, so the set has a stale entry to correct.
        XCTAssertEqual(store.get(UserSettings.displayName), "Anonymous")

        store.set("fresh", for: UserSettings.displayName)
        XCTAssertEqual(store.get(UserSettings.displayName), "fresh")
    }

    func testRemoveRefreshesTheMemo() {
        store.set("doomed", for: UserSettings.displayName)
        XCTAssertEqual(store.get(UserSettings.displayName), "doomed")

        store.remove(UserSettings.displayName)
        XCTAssertEqual(store.get(UserSettings.displayName), "Anonymous")
    }

    func testMemoizedValuesAreScopedToTheProviderInstance() {
        store.set("owned", for: UserSettings.displayName)
        XCTAssertEqual(store.get(UserSettings.displayName), "owned")

        // A second provider on the same service starts with an empty memo and so
        // reads the keychain — the memo is per-instance state, not a global.
        let other = KeychainSecureSettingsStorageProvider(service: serviceID)
        XCTAssertEqual(other.get(UserSettings.displayName), "owned")
    }

    // MARK: - isSecure flag

    func testProviderReportsSecure() {
        XCTAssertTrue(store.isSecure)
    }
}
