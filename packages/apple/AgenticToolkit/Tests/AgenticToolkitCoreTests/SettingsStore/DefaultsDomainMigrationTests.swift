import XCTest
@testable import AgenticToolkitCore

final class DefaultsDomainMigrationTests: XCTestCase {
    private let defaults = UserDefaults.standard
    private var legacy = ""
    private var current = ""

    override func setUp() {
        super.setUp()
        let tag = UUID().uuidString
        legacy = "com.example.migration-test.legacy.\(tag)"
        current = "com.example.migration-test.current.\(tag)"
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: legacy)
        defaults.removePersistentDomain(forName: current)
        super.tearDown()
    }

    func testCopiesLegacySettingsIntoAnEmptyDomain() {
        defaults.setPersistentDomain(["theme": "dark", "count": 3], forName: legacy)

        XCTAssertTrue(DefaultsDomainMigration.migrateIfNeeded(from: legacy, to: current))

        let copied = defaults.persistentDomain(forName: current)
        XCTAssertEqual(copied?["theme"] as? String, "dark")
        XCTAssertEqual(copied?["count"] as? Int, 3)
        XCTAssertNotNil(defaults.persistentDomain(forName: legacy), "legacy domain is kept for a downgrade")
    }

    /// A setting already made under the new id is the user's latest word.
    func testNeverOverwritesADomainThatAlreadyHoldsSettings() {
        defaults.setPersistentDomain(["theme": "dark"], forName: legacy)
        defaults.setPersistentDomain(["theme": "light"], forName: current)

        XCTAssertFalse(DefaultsDomainMigration.migrateIfNeeded(from: legacy, to: current))
        XCTAssertEqual(defaults.persistentDomain(forName: current)?["theme"] as? String, "light")
    }

    func testDoesNothingWithoutLegacySettings() {
        XCTAssertFalse(DefaultsDomainMigration.migrateIfNeeded(from: legacy, to: current))
        XCTAssertTrue(defaults.persistentDomain(forName: current)?.isEmpty ?? true)
    }

    func testIsIdempotent() {
        defaults.setPersistentDomain(["theme": "dark"], forName: legacy)

        XCTAssertTrue(DefaultsDomainMigration.migrateIfNeeded(from: legacy, to: current))
        XCTAssertFalse(DefaultsDomainMigration.migrateIfNeeded(from: legacy, to: current))
    }
}
