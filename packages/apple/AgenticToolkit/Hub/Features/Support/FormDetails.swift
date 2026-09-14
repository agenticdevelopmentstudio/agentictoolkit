import AgenticToolkitHTDV
import Foundation

/// Factories for the two detail panes every feature uses: an editable form and a read-only notice.
public enum FormDetails {
    public static let unavailableMessage = "Not available in this version"

    public static func form(
        id: String, title: String, spec: FormSpec, values: [String: FormValue], blockedReason: String? = nil
    ) -> HTDVDetail {
        HTDVDetail(id: id, title: title) {
            let state = FormState(spec: spec, values: values)
            state.blockedReason = blockedReason
            return FormViewController(state: state, markdownEditing: HubModules.markdownEditing)
        }
    }

    public static func notice(id: String, title: String, message: String) -> HTDVDetail {
        let spec = FormSpec(sections: [
            FormSection(fields: [.readOnly(FormReadOnlyField(key: "notice", label: title))])
        ])
        return form(id: id, title: title, spec: spec, values: ["notice": .string(message)])
    }
}
