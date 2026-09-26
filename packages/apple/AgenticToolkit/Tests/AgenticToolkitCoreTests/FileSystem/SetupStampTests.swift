import XCTest
@testable import AgenticToolkitCore

final class SetupStampTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testMissingStampNeedsSetup() {
        XCTAssertTrue(SetupStamp.needsSetup(bundleVersion: "2.154.0", stampURL: dir.appendingPathComponent("s")))
    }

    func testRecordedSameVersionDoesNotNeedSetup() throws {
        let url = dir.appendingPathComponent("nested/s")
        try SetupStamp.record(bundleVersion: "2.154.0", at: url)
        XCTAssertFalse(SetupStamp.needsSetup(bundleVersion: "2.154.0", stampURL: url))
    }

    func testDifferentVersionNeedsSetupInEitherDirection() throws {
        let url = dir.appendingPathComponent("s")
        try SetupStamp.record(bundleVersion: "2.154.0", at: url)
        XCTAssertTrue(SetupStamp.needsSetup(bundleVersion: "2.155.0", stampURL: url))
        XCTAssertTrue(SetupStamp.needsSetup(bundleVersion: "2.153.0", stampURL: url))
    }

    func testWhitespaceInStampIsIgnored() throws {
        let url = dir.appendingPathComponent("s")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "2.154.0\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertFalse(SetupStamp.needsSetup(bundleVersion: "2.154.0", stampURL: url))
    }

    func testDefaultURLShape() {
        let url = SetupStamp.defaultURL(supportDirectoryName: "com.example.app")
        XCTAssertTrue(url.path.hasSuffix("Library/Application Support/com.example.app/last-setup-version"))
    }
}
