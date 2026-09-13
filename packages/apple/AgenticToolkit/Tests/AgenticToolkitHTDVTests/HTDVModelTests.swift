import XCTest
@testable import AgenticToolkitHTDV

final class HTDVModelTests: XCTestCase {
    func testItemDefaults() {
        let item = HTDVItem(id: "a", label: "Alpha")
        XCTAssertNil(item.sublabel)
        XCTAssertNil(item.systemImage)
        XCTAssertFalse(item.dividerAfter)
        XCTAssertEqual(item.leadsTo, .list)
        XCTAssertNil(item.badge)
    }

    func testItemHashableUsesAllFields() {
        let itemWithCount3 = HTDVItem(id: "a", label: "Alpha", badge: .count(3))
        let itemWithCount4 = HTDVItem(id: "a", label: "Alpha", badge: .count(4))
        XCTAssertNotEqual(itemWithCount3, itemWithCount4)
        XCTAssertEqual(itemWithCount3, HTDVItem(id: "a", label: "Alpha", badge: .count(3)))
    }

    func testLevelDefaults() {
        let level = HTDVLevel(id: "root", title: "Root", items: [])
        XCTAssertEqual(level.emptyMessage, "Nothing here yet")
        XCTAssertNil(level.createAction)
    }

    func testCellContentFromListItem() {
        let item = HTDVItem(
            id: "p",
            label: "Personas",
            sublabel: "3 items",
            systemImage: "person.2",
            leadsTo: .list
        )
        let cell = HTDVCellContent(item: item)
        XCTAssertEqual(cell.label, "Personas")
        XCTAssertEqual(cell.sublabel, "3 items")
        XCTAssertEqual(cell.systemImage, "person.2")
        XCTAssertTrue(cell.isDisclosing)
    }

    func testCellContentFromDetailItemIsNotDisclosing() {
        let item = HTDVItem(
            id: "s",
            label: "Settings",
            leadsTo: .detail,
            badge: .dot(.green)
        )
        let cell = HTDVCellContent(item: item)
        XCTAssertFalse(cell.isDisclosing)
        XCTAssertEqual(cell.badge, .dot(.green))
    }

    @MainActor
    func testDetailMakeProducesViewController() {
        let detail = HTDVDetail(id: "d", title: "Detail") { PlatformViewController() }
        XCTAssertEqual(detail.title, "Detail")
        _ = detail.make()
    }
}
