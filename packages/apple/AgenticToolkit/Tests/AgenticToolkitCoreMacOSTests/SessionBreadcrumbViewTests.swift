import AppKit
import Testing
@testable import AgenticToolkitCoreMacOS

/// The breadcrumb heads rows in two windows, so what is asserted here is what
/// the two are promised to agree on: the segments drawn, the colour each one
/// carries, and what a changed trail costs.
@Suite("SessionBreadcrumbView")
@MainActor
struct SessionBreadcrumbViewTests {

    private func makeView(
        project: String = "stenographer",
        branch: String = "conversations",
        name: String = "tidy the feed"
    ) -> SessionBreadcrumbView {
        SessionBreadcrumbView(crumbs: .init(project: project, branch: branch, name: name))
    }

    @Test("every segment is a label, in reading order")
    func segmentsInOrder() {
        let view = makeView()

        #expect(view.segmentLabels.map(\.stringValue)
            == ["stenographer", "conversations", "tidy the feed"])
    }

    @Test("a separator sits between segments and never at either end")
    func separatorsBetweenOnly() {
        let view = makeView()
        let texts = view.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }

        #expect(texts == ["stenographer", SessionBreadcrumbView.separator,
                          "conversations", SessionBreadcrumbView.separator, "tidy the feed"])
    }

    /// A session outside a repo, or one whose title has not been written yet,
    /// reads as a shorter trail — not as one with a dangling `»`.
    @Test("a missing segment is dropped, separator and all")
    func missingSegmentsDropped() {
        let view = makeView(branch: "", name: "")
        let texts = view.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }

        #expect(texts == ["stenographer"])
    }

    /// The name is the only part a human chose, and it is the only part in
    /// Claude's orange — that is how a reader picks it out of the trail.
    @Test("the name carries its own colour, the context the theme's")
    func coloursByRole() {
        let view = makeView()
        view.applyTheme(ThemePaletteObserver.currentPalette)

        #expect(view.nameLabel?.textColor == SessionBreadcrumbView.nameColor)
        #expect(view.contextLabels.allSatisfy { $0.textColor != SessionBreadcrumbView.nameColor })
    }

    @Test("every segment is set at one size")
    func oneFont() {
        let view = makeView()
        view.applyTheme(ThemePaletteObserver.currentPalette)
        let sizes = Set(view.segmentLabels.compactMap { $0.font?.pointSize })

        #expect(sizes.count == 1)
    }

    /// A branch checked out or a session renamed is new text in labels that are
    /// already there. Rebuilding them instead is what makes a trail flicker.
    @Test("a rename writes into the labels that are there")
    func renameKeepsLabels() {
        let view = makeView()
        let before = view.segmentLabels

        view.crumbs = .init(project: "stenographer", branch: "main", name: "tidy the feed")

        #expect(view.segmentLabels.map(ObjectIdentifier.init)
            == before.map(ObjectIdentifier.init))
        #expect(view.contextLabels.last?.stringValue == "main")
    }

    @Test("a segment that appears rebuilds the trail")
    func appearingSegmentRebuilds() {
        let view = makeView(name: "")
        #expect(view.nameLabel == nil)

        view.crumbs = .init(project: "stenographer", branch: "conversations", name: "now named")

        #expect(view.nameLabel?.stringValue == "now named")
        #expect(view.segmentLabels.count == 3)
    }

    /// The labels abstain from the fitting width on purpose — one long session
    /// name once dragged a window out to forty thousand points — so the trail's
    /// own minimum is what a host has to measure it by.
    @Test("the whole trail fits at its minimum width")
    func fitsAtMinimumWidth() {
        let view = makeView()
        view.applyTheme(ThemePaletteObserver.currentPalette)
        view.frame = NSRect(x: 0, y: 0, width: view.minimumWidth, height: 40)
        view.layoutSubtreeIfNeeded()

        for label in view.segmentLabels {
            #expect(ceil(label.frame.width) + 0.5 >= ceil(label.intrinsicContentSize.width),
                    "\(label.stringValue) was truncated at the trail's minimum width")
        }
    }

    @Test("the trail reads as one line for a screen reader")
    func lineJoinsTheSegments() {
        #expect(makeView().crumbs.line
            == "stenographer » conversations » tidy the feed")
    }
}
