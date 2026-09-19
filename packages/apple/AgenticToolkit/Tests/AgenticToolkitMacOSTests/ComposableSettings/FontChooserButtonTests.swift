import AppKit
import Foundation
import Testing

import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The control every font row in the app now presses.
///
/// Two of these are the bugs the control exists to not have. A button that
/// drew the sample at the font's own size tore a 48 pt title role out of its
/// row, and a button that *stored* the clamped sample size instead rewrote that
/// role to 12 pt the moment the panel was opened on it. Drawn size and recorded
/// size are therefore different facts, and these say so.
@Suite("FontChooserButton")
@MainActor
struct FontChooserButtonTests {

    @Test("a chosen font is drawn at the sample size, whatever size it was chosen at")
    func drawsTheSampleAtOneSize() throws {
        let button = ComposableSettings.FontChooserButton()
        let menlo = try #require(NSFont(name: "Menlo", size: 48))

        button.show(menlo, title: "Menlo — 48 pt")

        #expect(button.title == "Menlo — 48 pt")
        #expect(button.font?.pointSize == ComposableSettings.FontChooserButton.sampleSize)
        #expect(button.font?.familyName == menlo.familyName)
    }

    @Test("the size the font was chosen at survives being drawn small")
    func keepsTheChosenSize() throws {
        let button = ComposableSettings.FontChooserButton()
        let menlo = try #require(NSFont(name: "Menlo", size: 48))

        button.show(menlo, title: "Menlo — 48 pt")

        // What the panel will open on, and what a pick is converted from. Were
        // this the drawn font, picking a face would silently resize the role.
        #expect(button.selectedFont?.pointSize == 48)
    }

    @Test("no font chosen draws the title in the system font and records nothing")
    func systemFontWhenNothingIsChosen() {
        let button = ComposableSettings.FontChooserButton()

        button.show(nil, title: "System")

        #expect(button.selectedFont == nil)
        #expect(button.title == "System")
        #expect(button.font?.pointSize == ComposableSettings.FontChooserButton.sampleSize)
    }

    @Test("the panel offers the parts that pick a font and nothing that writes color")
    func offersOnlyTheFontModes() {
        let button = ComposableSettings.FontChooserButton()

        let modes = button.validModesForFontPanel(NSFontPanel.shared)

        #expect(modes.contains(.face))
        #expect(modes.contains(.size))
        #expect(modes.contains(.collection))
        #expect(!modes.contains(.shadowEffect))
        #expect(!modes.contains(.underlineEffect))
        #expect(!modes.contains(.strikethroughEffect))
        #expect(!modes.contains(.textColorEffect))
    }

    @Test("leaving its window hands the font manager's target back")
    func releasesTheFontManagerTarget() {
        let button = ComposableSettings.FontChooserButton()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView?.addSubview(button)
        // `NSFontManager.target` is `unowned(unsafe)`: a panel left pointing at
        // a freed row writes into freed memory rather than failing.
        NSFontManager.shared.target = button

        button.removeFromSuperview()

        #expect(NSFontManager.shared.target == nil)
    }
}
