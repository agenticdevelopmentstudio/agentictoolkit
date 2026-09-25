import XCTest
@testable import AgenticToolkitCore

final class UniqueNameTests: XCTestCase {

    func testSkipsEveryTakenSuffix() {
        XCTAssertEqual(UniqueName.next(base: "New Client", taken: []), "New Client")
        XCTAssertEqual(UniqueName.next(base: "New Client", taken: ["New Client"]), "New Client 2")
        XCTAssertEqual(UniqueName.next(base: "misc", taken: ["misc", "misc 2", "misc 3"]), "misc 4")
    }

    /// A rename is refused the way a person reading the list would see a clash.
    func testCollisionIgnoresCaseAndSurroundingWhitespace() {
        XCTAssertTrue(UniqueName.collides("acme ", with: ["Acme"]))
        XCTAssertTrue(UniqueName.collides("ACME", with: ["Beta", " acme"]))
        XCTAssertFalse(UniqueName.collides("Acme Corp", with: ["Acme"]))
        XCTAssertFalse(UniqueName.collides("Acme", with: []))
    }
}

final class UTF8SearchTests: XCTestCase {

    func testFindsANeedleByItsBytes() {
        let line = #"{"type":"summary","summary":"Café résumé"}"#
        XCTAssertTrue(line.containsUTF8(#""type":"summary""#))
        XCTAssertTrue(line.containsUTF8(Array("résumé".utf8)))
        XCTAssertFalse(line.containsUTF8("assistant"))
        XCTAssertTrue(line.containsUTF8(""), "an empty needle is in everything")
        XCTAssertFalse("".containsUTF8("x"))
    }
}
