import Foundation
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

extension BillingUserSettings {
    /// Billing settings under a prefix of the tests' own, so a test that
    /// changes one never touches a real app's.
    static let forTests = BillingUserSettings(keys: BillingSettingsKeys(prefix: "agentictoolkit_tests_billing_"))
}

extension BillingUIContext {
    /// A billing window's context for a test: its model, the tests' settings.
    @MainActor
    static func forTests(model: BillingModel) -> BillingUIContext {
        BillingUIContext(model: model, settings: .forTests)
    }
}

/// A cell as a test reads it: the text the card draws, a placeholder in
/// parentheses, a switch as "on"/"off", a dot as "●"/"○", no cell as "-".
@MainActor
func shownCell(
    _ value: ComposableSettings.EditableTableCellValue?,
    timeZone: TimeZone = .current, locale: Locale = .current
) -> String {
    switch value {
    case .toggle(let isOn): return isOn ? "on" : "off"
    case .indicator(let isOn): return isOn ? "●" : "○"
    case nil: return "-"
    default:
        let (text, placeholder) = ComposableSettings.EditableTableCard.display(
            value, timeZone: timeZone, locale: locale)
        return text.isEmpty ? placeholder.map { "(\($0))" } ?? "" : text
    }
}
