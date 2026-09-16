import SwiftUI
import AppKit
import AIPluginKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// Editor for one configuration: rename and per-template fields.
///
/// Model choice and the try-it-out chat deliberately live in the LLM Chat window
/// (`LLMChatViewController`), not here: both need the whole width of a window, and
/// keeping a live chat session per configuration meant every provider in the
/// sidebar held an open backend whether or not anyone had looked at it. The "Chat"
/// button below opens that window pointed at this configuration.
struct LLMProviderEditorView: View {

    let configuration: AIProviderConfiguration
    @ObservedObject var viewModel: LLMProvidersListViewModel
    @State private var name: String
    /// The chosen model, mirrored so it can be refreshed when the chat window (or
    /// any other surface) writes a new one while this editor is on screen.
    @State private var model: String = ""

    @Environment(\.theme) private var theme

    init(configuration: AIProviderConfiguration, viewModel: LLMProvidersListViewModel) {
        self.configuration = configuration
        self.viewModel = viewModel
        _name = State(initialValue: configuration.name)
    }

    private var template: AIPluginDescriptor.ProviderTemplate? {
        viewModel.pluginManager.template(
            pluginIdentifier: configuration.pluginIdentifier, templateId: configuration.templateId
        )
    }

    private var fields: [AIPluginDescriptor.Field] {
        guard let template else { return [] }
        return viewModel.pluginManager.fields(
            pluginIdentifier: configuration.pluginIdentifier, template: template
        )
    }

    /// The provider identity shown as the detail-pane title (distinct from the
    /// user's editable Name below), e.g. "Anthropic API".
    private var title: String { template?.displayName ?? configuration.name }

    /// The model this configuration is pointed at, straight from the store. The
    /// chooser moved to the chat window, so this row is the only place Settings still
    /// says which model a provider will use — without it, "Chat…" was the only way to
    /// find out, and opening a chat is a poor way to ask a question.
    private var storedModel: String {
        guard let template else { return "" }
        return AIProviderConfigStore.selectedModel(config: configuration, template: template)
    }

    /// Why "Chat…" is unavailable, or what it does when it isn't. A configuration
    /// whose plugin failed to load has no template, and the chat window can't build a
    /// backend without one — it would open on an empty provider row and fail at the
    /// first send, with nothing on screen saying why.
    private var chatHint: String {
        template == nil
            ? "This provider's plugin isn't loaded, so it can't be used."
            : "Try this provider out and choose its model."
    }

    /// Provider · LLM · Config Type, e.g. "Anthropic · Claude · API Key".
    private var subtitle: String {
        guard let template else { return configuration.templateId }
        var parts = [template.resolvedProvider]
        if !template.resolvedLLM.isEmpty { parts.append(template.resolvedLLM) }
        parts.append(template.resolvedConfigType)
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.font(.title))
                Text(subtitle)
                    .font(theme.font(.caption))
                    .foregroundStyle(theme.secondaryText)
            }

            Form {
                TextField("Name", text: $name)
                    .onSubmit {
                        viewModel.rename(configuration.id, to: name)
                        name = viewModel.configuration(for: configuration.id)?.name ?? name
                    }

                ForEach(fields, id: \.key) { field in
                    if field.isSecret {
                        SecureField(field.label, text: fieldBinding(field))
                    } else {
                        TextField(field.label, text: fieldBinding(field),
                                  prompt: field.placeholder.map(Text.init))
                    }
                }

                LabeledContent("Model") {
                    Text(model.isEmpty ? "None chosen" : model)
                        .foregroundStyle(model.isEmpty ? theme.secondaryText : theme.primaryText)
                }
            }

            HStack {
                Button("Chat…") { viewModel.onRequestChat?(configuration) }
                    .disabled(template == nil)
                Text(chatHint)
                    .font(theme.font(.caption))
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { model = storedModel }
        // The chat window writes the same key from its own model chooser, so the row
        // has to re-read rather than snapshot once: any settings write is cheap to
        // answer, and this editor stays on screen behind that window.
        .onReceive(UserSettings.shared.changes) { _ in model = storedModel }
    }

    private func fieldBinding(_ field: AIPluginDescriptor.Field) -> Binding<String> {
        let setting = AIProviderConfigStore.fieldSetting(config: configuration.id, field: field)
        return Binding(get: { setting.currentValue }, set: { setting.value = $0 })
    }
}
