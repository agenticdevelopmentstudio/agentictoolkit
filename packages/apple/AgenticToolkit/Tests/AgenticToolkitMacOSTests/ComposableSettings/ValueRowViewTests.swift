import AppKit
import Foundation
import Testing

import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A read-only settings row: a name on the left, a figure on the right.
@Suite("ValueRowView")
@MainActor
struct ValueRowViewTests {

    @Test("title and value are drawn, and the value can change")
    func showsTitleAndValue() {
        let row = ComposableSettings.ValueRowView(title: "Unbilled", value: "—")
        #expect(row.label.stringValue == "Unbilled")
        #expect(row.valueLabel.stringValue == "—")

        row.value = "2 billables · 2.25 h"
        #expect(row.valueLabel.stringValue == "2 billables · 2.25 h")
        #expect(row.value == "2 billables · 2.25 h")
    }

    @Test("VoiceOver hears the figure under the row's name")
    func valueIsLabelledForAccessibility() {
        let row = ComposableSettings.ValueRowView(title: "Paid", value: "$10.00")
        #expect(row.valueLabel.accessibilityLabel() == "Paid")
        #expect(row.valueLabel.isSelectable, "a total is something people copy into an invoice")
    }
}
