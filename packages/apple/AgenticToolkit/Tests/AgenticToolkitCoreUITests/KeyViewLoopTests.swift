import AppKit
import Testing
@testable import AgenticToolkitCoreUI

@MainActor
@Suite("KeyViewLoop")
struct KeyViewLoopTests {

    /// A field in a window, because `acceptsFirstResponder` on a text field is
    /// answered partly by whether it is editable and enabled.
    private func makeField(enabled: Bool = true, hidden: Bool = false) -> NSTextField {
        let field = NSTextField()
        field.isEditable = true
        field.isEnabled = enabled
        field.isHidden = hidden
        return field
    }

    private func host(_ views: [NSView]) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: true)
        for view in views { window.contentView?.addSubview(view) }
        return window
    }

    @Test("Tab walks the named fields and comes back round")
    func theLoopIsACycle() {
        let first = makeField()
        let second = makeField()
        _ = host([first, second])

        let loop = KeyViewLoop([first, second])
        loop.refresh()

        #expect(first.nextKeyView === second)
        // The half the automatic loop got wrong: leaving the last field has to
        // land back on the first, or a field can be tabbed out of and never
        // into.
        #expect(second.nextKeyView === first)
        #expect(loop.first === first)
    }

    @Test("A disabled field is skipped rather than made a dead stop")
    func aDisabledFieldDropsOut() {
        let filter = makeField()
        let composer = makeField(enabled: false)
        let other = makeField()
        _ = host([filter, composer, other])

        let loop = KeyViewLoop([filter, composer, other])
        loop.refresh()

        #expect(filter.nextKeyView === other)
        #expect(other.nextKeyView === filter)
    }

    @Test("A hidden field is skipped — a collapsed pane hides, it does not disable")
    func aHiddenFieldDropsOut() {
        let filter = makeField(hidden: true)
        let composer = makeField()
        _ = host([filter, composer])

        let loop = KeyViewLoop([filter, composer])
        loop.refresh()

        #expect(loop.first === composer)
        #expect(composer.nextKeyView === composer)
    }

    @Test("One participant points at itself, so Tab stays put")
    func aLoneFieldStaysPut() {
        let composer = makeField()
        _ = host([composer])

        let loop = KeyViewLoop([composer])
        loop.refresh()

        #expect(composer.nextKeyView === composer)
    }

    @Test("Turning a field back on puts it back in the cycle")
    func refreshRewires() {
        let filter = makeField()
        let composer = makeField(enabled: false)
        _ = host([filter, composer])

        let loop = KeyViewLoop([filter, composer])
        loop.refresh()
        #expect(filter.nextKeyView === filter)

        composer.isEnabled = true
        loop.refresh()
        #expect(filter.nextKeyView === composer)
        #expect(composer.nextKeyView === filter)
    }

    @Test("Nothing focusable leaves no first responder to offer")
    func anEmptyLoopIsHarmless() {
        let field = makeField(enabled: false)
        _ = host([field])

        let loop = KeyViewLoop([field])
        loop.refresh()

        #expect(loop.first == nil)
    }
}
