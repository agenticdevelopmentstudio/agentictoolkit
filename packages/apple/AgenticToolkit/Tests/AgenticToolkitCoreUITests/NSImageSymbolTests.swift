import AppKit
import Testing
@testable import AgenticToolkitCoreUI

/// Review V19-e: a symbol name this macOS does not ship must not crash the
/// view that asked for it.
@Suite("NSImage.symbol")
@MainActor
struct NSImageSymbolTests {

    @Test func aKnownSymbolIsTheSystemImage() {
        let image = NSImage.symbol(named: "plus", accessibilityDescription: "Add")
        #expect(image.size.width > 0)
        #expect(image.accessibilityDescription == "Add")
    }

    @Test func anUnknownSymbolIsABlankTemplateThatKeepsItsDescription() {
        let image = NSImage.symbol(named: "no.such.symbol.anywhere", accessibilityDescription: "Stop")
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 16, height: 16))
        #expect(image.accessibilityDescription == "Stop")
    }
}
