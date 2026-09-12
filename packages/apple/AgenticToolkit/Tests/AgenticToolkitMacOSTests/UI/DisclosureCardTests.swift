import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// Pins the rules a stack of folding cards lives by: the arithmetic of the
/// remembered set (`CardFoldMemory`); the one that a fold is a change of HEIGHT
/// — a card is exactly as wide shut as it is open, so a window that hugs its
/// content cannot jump sideways when the reader clicks a disclosure triangle;
/// and where a card's standing goes now that it is a corner badge rather than a
/// reserved slot on the masthead.
@MainActor
final class DisclosureCardTests: XCTestCase {

    // MARK: - The remembered set

    func testFoldingACardRecordsItAndUnfoldingForgetsIt() {
        var keys = CardFoldMemory.toggling([], key: "usage", collapsed: true)
        XCTAssertEqual(keys, ["usage"])

        keys = CardFoldMemory.toggling(keys, key: "usage", collapsed: false)
        XCTAssertEqual(keys, [], "open is ABSENT, not stored as false")
    }

    func testFoldingTwiceDoesNotStoreTheCardTwice() {
        let once = CardFoldMemory.toggling(["a"], key: "usage", collapsed: true)
        let twice = CardFoldMemory.toggling(once, key: "usage", collapsed: true)
        XCTAssertEqual(twice, ["a", "usage"])
    }

    func testUnfoldingOneCardLeavesTheOthersFolded() {
        XCTAssertEqual(
            CardFoldMemory.toggling(["a", "usage", "b"], key: "usage", collapsed: false),
            ["a", "b"]
        )
    }

    func testAMemoryReadsAndWritesTheHostsStore() {
        var stored: [String] = []
        var rebuilds = 0
        let memory = CardFoldMemory(
            read: { stored },
            write: { stored = $0 },
            rebuild: { rebuilds += 1 }
        )
        XCTAssertFalse(memory.isCollapsed("a"))

        memory.setCollapsed(true, key: "a")
        XCTAssertEqual(stored, ["a"])
        XCTAssertTrue(memory.isCollapsed("a"))
        // The rebuild is deferred to the next turn of the runloop on purpose:
        // it tears down the very button that is still dispatching the click.
        XCTAssertEqual(rebuilds, 0, "a rebuild must not run inside the toggle's own action")
    }

    func testACardBuiltThroughTheMemoryOpensInTheRememberedState() {
        let memory = CardFoldMemory(read: { ["shut"] }, write: { _ in }, rebuild: {})

        XCTAssertTrue(memory.card(key: "shut", title: "Shut", scaledSize: 13).isCollapsed)
        XCTAssertFalse(memory.card(key: "open", title: "Open", scaledSize: 13).isCollapsed)
    }

    // MARK: - Folding is a change of height, never of width

    private func card(isCollapsed: Bool) -> DisclosureCardView {
        let card = DisclosureCardView(
            title: "mike@example.com",
            titleIsAccent: true,
            summary: [
                .init(name: "5H", value: "23%", colorName: "blue"),
                .init(name: "7D", value: "12%", colorName: "green")
            ],
            status: .init(
                symbolName: "octagon.fill", colorName: "red", accessibilityLabel: "Spent"
            ),
            isCollapsed: isCollapsed,
            scaledSize: 13
        )
        let wide = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 60))
        wide.widthAnchor.constraint(equalToConstant: 600).isActive = true
        // A height as well as a width: the folded card writes its summary on a
        // row of its own, so a card whose content measures zero points tall is
        // TALLER shut than open, and correctly so. What the fold is for is
        // putting away content, and content has a size.
        wide.heightAnchor.constraint(equalToConstant: 60).isActive = true
        card.addContent(wide)
        // Hosted rather than merely measured: a card that was never given a
        // size lays its subviews out against a frame nothing set, so anything
        // about WHERE a subview lands has to be read off a laid-out card.
        host(card, width: 700)
        return card
    }

    /// Puts a card in a view of a known width and lays it out, returning the
    /// host so a test can compare the two.
    @discardableResult
    private func host(_ card: DisclosureCardView, width: CGFloat) -> NSView {
        card.translatesAutoresizingMaskIntoConstraints = false
        let host = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
        host.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            card.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()
        return host
    }

    func testAFoldedCardIsExactlyAsWideAsAnOpenOne() {
        // The bug this pins: a folded card that dropped its content asked for a
        // narrower window, so every disclosure click moved the window sideways.
        XCTAssertEqual(card(isCollapsed: true).fittingSize.width,
                       card(isCollapsed: false).fittingSize.width,
                       accuracy: 0.5)
    }

    func testAFoldedCardIsShorterThanAnOpenOne() {
        // …and the fold still does the one thing it is for.
        XCTAssertLessThan(card(isCollapsed: true).fittingSize.height,
                          card(isCollapsed: false).fittingSize.height)
    }

    func testACardIsNeverNarrowerThanTheContentItIsHiding() {
        let card = card(isCollapsed: true)
        XCTAssertGreaterThanOrEqual(card.fittingSize.width, 600,
                                    "the hidden content still sets the card's width floor")
    }

    func testAFoldedCardIsAsWideAsAnOpenOneEvenWhenItsSummaryIsWiderThanItsContent() {
        // The other half of the same rule, and the one the masthead floor is
        // for: with the summary's row out of the OPEN card's layout, the width
        // it will want on folding has to be reserved somewhere that does not
        // depend on which state the card is in.
        func narrow(isCollapsed: Bool) -> DisclosureCardView {
            let card = DisclosureCardView(
                title: "me@x.com",
                titleIsAccent: true,
                summary: [
                    .init(name: "5H", value: "23%", colorName: "blue"),
                    .init(name: "7D", value: "12%", colorName: "green")
                ],
                isCollapsed: isCollapsed,
                scaledSize: 13
            )
            let tiny = NSView()
            tiny.translatesAutoresizingMaskIntoConstraints = false
            tiny.widthAnchor.constraint(equalToConstant: 40).isActive = true
            tiny.heightAnchor.constraint(equalToConstant: 20).isActive = true
            card.addContent(tiny)
            card.layoutSubtreeIfNeeded()
            return card
        }
        XCTAssertEqual(narrow(isCollapsed: true).fittingSize.width,
                       narrow(isCollapsed: false).fittingSize.width,
                       accuracy: 0.5)
    }

    // MARK: - The masthead is a bar, not the first row of the content

    /// The bar itself, found by position rather than by outlet: it is the one
    /// thing inside the surface, and the surface is the one thing under the card
    /// (the badge and the stack are added after it).
    private func titlebar(of card: DisclosureCardView) -> NSView? {
        card.subviews.first?.subviews.first
    }

    /// A card carrying whatever a test needs and nothing it doesn't, hosted and
    /// laid out. `card(isCollapsed:)` above always has a summary, a standing and
    /// content, and what the bar does when one of those is ABSENT is most of
    /// what these tests are about.
    private func bare(
        isCollapsed: Bool,
        summary: [DisclosureCardView.SummaryPart] = [],
        titleAccessory: NSView? = nil
    ) -> DisclosureCardView {
        let card = DisclosureCardView(
            title: "mike@example.com",
            titleIsAccent: true,
            titleAccessory: titleAccessory,
            summary: summary,
            status: .init(
                symbolName: "octagon.fill", colorName: "red", accessibilityLabel: "Spent"
            ),
            isCollapsed: isCollapsed,
            scaledSize: 13
        )
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 120))
        content.widthAnchor.constraint(equalToConstant: 600).isActive = true
        content.heightAnchor.constraint(equalToConstant: 120).isActive = true
        card.addContent(content)
        host(card, width: 700)
        return card
    }

    func testTheBarCapsTheCardRatherThanFillingIt() {
        let card = bare(isCollapsed: false)
        guard let bar = titlebar(of: card), let name = field("mike@example.com", in: card) else {
            return XCTFail("every card has a titlebar and a name on it")
        }

        // Edge to edge and starting at the very top: the bar is the card's own
        // cap, which is what lets the surface's rounded corners clip it.
        XCTAssertEqual(bar.frame.width, card.frame.width, accuracy: 0.5)
        XCTAssertEqual(bar.frame.maxY, card.frame.height, accuracy: 0.5)
        // The name it carries is ON it — a bar the title had outgrown would be
        // a stripe behind nothing.
        let line = card.convert(name.bounds, from: name)
        XCTAssertGreaterThanOrEqual(line.minY, bar.frame.minY - 0.5)
        XCTAssertLessThanOrEqual(line.maxY, bar.frame.maxY + 0.5)
        // And it stops well short of the content, so it reads as a strip
        // capping the card rather than as the card's own background.
        XCTAssertLessThan(bar.frame.height, card.frame.height / 2)
    }

    func testAFoldedCardWithNothingToSayIsExactlyItsOwnTitlebar() {
        // The body leaves the layout entirely rather than standing there as an
        // empty stack between two insets — otherwise such a card ends in a
        // sliver of bare surface under the bar, which reads as a rendering bug.
        let card = bare(isCollapsed: true)
        guard let bar = titlebar(of: card) else { return XCTFail("no titlebar") }

        XCTAssertEqual(bar.frame.height, card.frame.height, accuracy: 0.5)
    }

    func testAFoldedCardWithASummaryStillKeepsABodyUnderItsBar() {
        // The summary IS the body in that case, so the bar is not the whole
        // card — the distinction the rule above turns on, and the reason it is
        // stated as "nothing to say" rather than "folded".
        let card = bare(
            isCollapsed: true,
            summary: [.init(name: "5H", value: "23%", colorName: "blue")]
        )
        guard let bar = titlebar(of: card) else { return XCTFail("no titlebar") }

        XCTAssertLessThan(bar.frame.height, card.frame.height - 1)
    }

    /// A mark of the host's own — a view the card is handed and does not own.
    private func mark() -> NSView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: "person.crop.circle",
                             accessibilityDescription: nil)
        view.setAccessibilityElement(false)
        return view
    }

    func testTheHostsMarkInFrontOfTheNameMovesNeitherTheBadgeNorTheToggle() {
        // The mark is nested inside the masthead's leading end, so the badge is
        // still the card's own subview and the toggle is still pinned to the
        // trailing edge. A mark that shifted either would have moved the one
        // thing a stack of cards is scanned by.
        let plain = bare(isCollapsed: false)
        let marked = bare(isCollapsed: false, titleAccessory: mark())
        guard let plainBadge = badge(of: plain), let markedBadge = badge(of: marked),
              let plainToggle = toggle(of: plain), let markedToggle = toggle(of: marked) else {
            return XCTFail("both cards draw a standing and a toggle")
        }

        XCTAssertEqual(markedBadge.frame.origin.x, plainBadge.frame.origin.x, accuracy: 0.5)
        XCTAssertEqual(markedBadge.frame.origin.y, plainBadge.frame.origin.y, accuracy: 0.5)
        XCTAssertEqual(marked.convert(markedToggle.bounds, from: markedToggle).maxX,
                       plain.convert(plainToggle.bounds, from: plainToggle).maxX,
                       accuracy: 0.5)
    }

    func testTheHostsMarkStandsInFrontOfTheNameExactlyAsHanded() {
        let given = mark()
        let card = bare(isCollapsed: false, titleAccessory: given)
        guard let name = field("mike@example.com", in: card), let line = name.superview else {
            return XCTFail("a card sets its name on a line of its own")
        }

        XCTAssertTrue(line.subviews.contains(given), "the mark goes on the title's own line")
        XCTAssertFalse(given.isHidden, "a card given a mark draws it")
        XCTAssertLessThanOrEqual(given.frame.maxX, name.frame.minX + 0.5)
        // The card paints nothing of the host's mark — not its colours, and not
        // its place in the accessibility tree. A host that hands over a view
        // has already decided both.
        XCTAssertFalse(given.isAccessibilityElement())
    }

    func testACardWithNoMarkLeavesNoGapWhereOneWouldHaveStood() {
        // Absent, not standing there empty: an arranged subview of zero width
        // still costs the stack its spacing, so a card with no mark would be
        // indented a few points further than one with — off the mark's own
        // leading edge, which is the alignment a stack of cards is read by.
        let plain = bare(isCollapsed: false)
        guard let name = field("mike@example.com", in: plain), let line = name.superview else {
            return XCTFail("a card sets its name on a line of its own")
        }

        XCTAssertEqual(line.subviews.count, 1, "the name is the whole of an unmarked title line")
        // Measured on the label's ALIGNMENT rect, not its frame: a text field's
        // frame overhangs its own text by a couple of points on each side, and
        // a stack lays out the alignment rects, so it is the alignment rect
        // that sits flush against the line's leading edge. Against the frame
        // this reads as a two-point negative indent that no card actually has.
        XCTAssertEqual(name.alignmentRect(forFrame: name.frame).minX, 0, accuracy: 0.5)
    }

    func testTheNameSitsNearerTheCardsBorderThanTheReadingsItCaps() {
        // The masthead is a heading, so it runs at a tighter gutter than the
        // rows under it — the same halving its vertical inset already takes.
        // The content keeps the gutter it always had, which is what lets this
        // move the name alone and leave every reading where it was.
        let card = DisclosureCardView(
            title: "mike@example.com", titleIsAccent: true, scaledSize: 13
        )
        let row = NSView()
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        card.addContent(row)
        host(card, width: 700)

        guard let name = field("mike@example.com", in: card), let line = name.superview else {
            return XCTFail("a card sets its name on a line of its own")
        }
        let titleX = card.convert(line.bounds, from: line).minX
        let rowX = card.convert(row.bounds, from: row).minX

        XCTAssertLessThan(titleX, rowX, "the name reaches nearer the border than the rows do")
        XCTAssertGreaterThan(titleX, 0, "and never touches it")
    }

    // MARK: - The standing is a corner badge

    /// The badge and the toggle, found by kind rather than by outlet — the card
    /// keeps both private, and what these tests are about is where they land.
    private func badge(of card: DisclosureCardView) -> NSImageView? {
        card.subviews.compactMap { $0 as? NSImageView }.first
    }

    private func toggle(of card: DisclosureCardView) -> NSButton? {
        func find(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton { return button }
            for child in view.subviews {
                if let found = find(child) { return found }
            }
            return nil
        }
        return find(card)
    }

    private func field(_ text: String, in card: DisclosureCardView) -> NSTextField? {
        func find(_ view: NSView) -> NSTextField? {
            if let label = view as? NSTextField, label.stringValue == text { return label }
            for child in view.subviews {
                if let found = find(child) { return found }
            }
            return nil
        }
        return find(card)
    }

    func testTheStandingSitsOnTheCardsTopRightCornerAndNeverOverTheToggle() {
        let card = card(isCollapsed: false)
        guard let badge = badge(of: card), let toggle = toggle(of: card) else {
            return XCTFail("a card with a standing draws a badge, and every card has a toggle")
        }
        XCTAssertFalse(badge.isHidden)
        // Centred on the corner the card actually DRAWS — the peak of its
        // rounded corner, a couple of points down and in from the square corner
        // of the frame, where there is no ink at all. Half the badge hangs off
        // the card from there. Measured on the ALIGNMENT rect, which is what the
        // constraints place — an SF Symbol carries alignment insets, so its
        // frame spills a point or two past the box the engine positioned.
        let peak = DisclosureCardView.cornerPeakInset
        XCTAssertGreaterThan(peak, 0, "a rounded corner peaks inside its frame")
        let box = badge.alignmentRect(forFrame: badge.frame)
        XCTAssertEqual(box.midX, card.bounds.maxX - peak, accuracy: 0.5)
        XCTAssertEqual(box.midY, card.bounds.maxY - peak, accuracy: 0.5)
        XCTAssertEqual(box.width, DisclosureCardView.cornerBadgeDiameter(scaledSize: 13),
                       accuracy: 0.5)
        // …and clear of the triangle, which is the whole constraint on where the
        // corner may be: the badge lives in the gutter to the RIGHT of it.
        let triangle = toggle.convert(toggle.bounds, to: card)
        XCTAssertFalse(badge.frame.intersects(triangle),
                       "the badge must not cover the disclosure toggle")
        XCTAssertGreaterThanOrEqual(badge.frame.minX, triangle.maxX)
    }

    /// A `CALayer` paints its own border above its sublayers, so a card that
    /// drew its own border would draw a hairline across the badge stamped on its
    /// corner. The border belongs to a subview under the badge instead — and the
    /// badge is the last subview, so it is drawn over it.
    func testTheBorderIsDrawnUnderTheBadgeRatherThanAcrossIt() {
        let card = card(isCollapsed: false)
        card.layoutSubtreeIfNeeded()
        XCTAssertEqual(card.layer?.borderWidth ?? 0, 0,
                       "the card itself must not draw a border over its own subviews")
        guard let surface = card.subviews.first else { return XCTFail("a card draws a surface") }
        XCTAssertGreaterThan(surface.layer?.borderWidth ?? 0, 0)
        XCTAssertNotNil(surface.layer?.backgroundColor)
        XCTAssertEqual(surface.frame, card.bounds, "the surface is the whole card")
        XCTAssertTrue(card.subviews.last === badge(of: card),
                      "the badge is drawn last, and so above the border")
    }

    func testACardWithNothingToReportDrawsNothing() {
        // No reserved slot any more: a card with no standing pays nothing for
        // the cards that have one.
        let card = DisclosureCardView(title: "Quiet", titleIsAccent: false, scaledSize: 13)
        card.layoutSubtreeIfNeeded()
        XCTAssertEqual(badge(of: card)?.isHidden, true)
    }

    func testTheStandingIsSpokenSinceItShareItsLineWithNothing() {
        let card = card(isCollapsed: true)
        XCTAssertEqual(badge(of: card)?.accessibilityLabel(), "Spent")
        XCTAssertEqual(badge(of: card)?.toolTip, "Spent")
    }

    // MARK: - The title gets the room the summary is not using

    func testWhenTheWindowCannotGrowItIsTheTitleThatYields() {
        // The card asks for room for both, but a window can refuse. Held to a
        // width neither fits in, it is the address that goes short: a truncated
        // address is still recognisable, and a truncated percentage is a lie.
        let title = "a-very-long-address@some-organisation.example.com"
        let card = DisclosureCardView(
            title: title,
            titleIsAccent: true,
            summary: [
                .init(name: "5H", value: "23%", colorName: "blue"),
                .init(name: "7D", value: "12%", colorName: "green")
            ],
            isCollapsed: true,
            scaledSize: 13
        )
        card.translatesAutoresizingMaskIntoConstraints = false
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        host.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            card.topAnchor.constraint(equalTo: host.topAnchor),
            // Required, so it beats the card's own width floor the way a window
            // the reader has dragged narrow does.
            card.widthAnchor.constraint(equalToConstant: 300)
        ])
        host.layoutSubtreeIfNeeded()

        guard let label = field(title, in: card) else { return XCTFail("no title") }
        XCTAssertLessThan(label.frame.width, label.fittingSize.width,
                          "there was no room for the whole address, so it must have gone short")
        XCTAssertGreaterThan(label.frame.width, 0)
    }

    func testACardAsksForTheRoomToWriteItsTitleWhole() {
        // The other half: the width a folded card asks for counts its title at
        // full length. Truncation is what a title does when the window can be
        // no wider — not what it does while the card is free to ask for another
        // forty points.
        let title = "a-very-long-address@some-organisation.example.com"
        let card = DisclosureCardView(
            title: title,
            titleIsAccent: true,
            summary: [
                .init(name: "5H", value: "23%", colorName: "blue"),
                .init(name: "7D", value: "12%", colorName: "green")
            ],
            isCollapsed: true,
            scaledSize: 13
        )
        let tiny = NSView()
        tiny.translatesAutoresizingMaskIntoConstraints = false
        tiny.widthAnchor.constraint(equalToConstant: 40).isActive = true
        tiny.heightAnchor.constraint(equalToConstant: 20).isActive = true
        card.addContent(tiny)

        // At exactly the width the card asks for — a window that hugs its
        // content gives it that and no more.
        host(card, width: card.fittingSize.width)
        guard let label = field(title, in: card) else { return XCTFail("no title") }
        XCTAssertGreaterThanOrEqual(label.frame.width, label.fittingSize.width - 0.5,
                                    "the address was squeezed by a card that could have grown")
    }

    // MARK: - The summary is a row of its own

    /// A folded card carrying the long address and the two readings.
    private func stacked(summary: [DisclosureCardView.SummaryPart]) -> DisclosureCardView {
        let card = DisclosureCardView(
            title: Self.longAddress,
            titleIsAccent: true,
            summary: summary,
            isCollapsed: true,
            scaledSize: 13
        )
        let tiny = NSView()
        tiny.translatesAutoresizingMaskIntoConstraints = false
        tiny.widthAnchor.constraint(equalToConstant: 40).isActive = true
        tiny.heightAnchor.constraint(equalToConstant: 20).isActive = true
        card.addContent(tiny)
        return card
    }

    private static let longAddress = "a-very-long-address@some-organisation.example.com"

    private static let readings: [DisclosureCardView.SummaryPart] = [
        .init(name: "5H", value: "23%", colorName: "blue"),
        .init(name: "7D", value: "12%", colorName: "green")
    ]

    func testTheSummaryIsWrittenUnderTheTitleRatherThanBesideIt() {
        let card = stacked(summary: Self.readings)
        host(card, width: card.fittingSize.width)

        guard let title = field(Self.longAddress, in: card) else { return XCTFail("no title") }
        guard let summary = field("5H: 23%  |  7D: 12%", in: card) else {
            return XCTFail("no summary")
        }
        guard let toggle = toggle(of: card) else { return XCTFail("no toggle") }
        let titleRect = card.convert(title.bounds, from: title)
        let summaryRect = card.convert(summary.bounds, from: summary)
        // The toggle's ALIGNMENT rect, not its frame: it draws an SF Symbol,
        // which carries insets, so the edge the engine lined the summary up
        // with is a point or two inside the image's box.
        let triangle = card.convert(toggle.alignmentRect(forFrame: toggle.bounds), from: toggle)
        XCTAssertLessThanOrEqual(summaryRect.maxY, titleRect.minY + 0.5,
                                 "the summary shares no line with the title")
        // And it is right-aligned across the WHOLE masthead — past where the
        // title's line stops to leave the toggle its corner, out to the same
        // edge the toggle ends on. That is what makes a stack of folded cards
        // read as a column of readings under one right edge.
        XCTAssertGreaterThan(summaryRect.maxX, titleRect.maxX)
        XCTAssertGreaterThanOrEqual(summaryRect.maxX, triangle.maxX,
                                    "out to the same edge the toggle ends on")
        XCTAssertLessThan(summaryRect.maxX, card.bounds.maxX,
                          "and inside the card's own padding")
    }

    func testALongerSummaryDoesNotWidenACardWhoseTitleIsWider() {
        // What stacking is FOR. Beside the title, every reading added its own
        // width plus a gap to a card that was already as wide as an address; on
        // a row of its own it costs nothing until it is wider than the address
        // itself, because the masthead needs the WIDER of its two rows and not
        // their sum. Two readings and one, against a title longer than either.
        XCTAssertEqual(stacked(summary: Self.readings).fittingSize.width,
                       stacked(summary: [Self.readings[0]]).fittingSize.width,
                       accuracy: 0.5)
    }
}
