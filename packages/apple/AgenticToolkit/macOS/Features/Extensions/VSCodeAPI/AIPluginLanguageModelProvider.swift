//
//  AIPluginLanguageModelProvider.swift
//  AgenticToolkit
//

import Foundation
import OSLog
import AgenticToolkitCore
import AIPluginKit

/// The production `ExtensionLanguageModelProviding`: it offers extensions the
/// chat models the user has already configured in this app's own LLM
/// Providers settings, and streams a `sendRequest` through the same
/// `AIPlugin` path the app's chat surface uses.
///
/// Task 5.7a's seam doc said no production conformer existed because "no
/// model provider exists in this host yet". That was true of a *model*
/// provider and not of this app: `AIProviderConfiguration` and
/// `AIProviderResolver` already join a configuration to its plugin template,
/// its stored credentials and its model, and `AIPluginChatBackend` already
/// drives one. This type reuses both rather than opening a second route to a
/// provider — it adds no transport, no credential handling and no request
/// shaping of its own.
///
/// ### Every configured model, not the selected one
///
/// `vscode.lm.selectChatModels` asks what the host *has*, and does its own
/// selector matching one layer up (`MainThreadLanguageModels`), so this lists
/// the cross product of every configuration the user has saved and every
/// model its template declares — not
/// `UserSettings.selectedAIProviderConfigurationId`, which is the app's own
/// chat choice and has nothing to say about what an extension may ask for.
///
/// ### The descriptor id is the routing key
///
/// `LanguageModelChatDescriptor.id` is what comes back on `sendRequest`, and
/// it is the *only* thing that does: the seam hands `streamResponse` a
/// descriptor, never a configuration. So the id is `<configuration
/// UUID>/<model>`, which is unique by construction (a UUID per configuration,
/// and a template never lists a model twice) and parses back to exactly the
/// pair needed to resolve the request. A model name containing a `/` — which
/// several gateways use — is preserved, because the split is on the *first*
/// separator only.
@MainActor
public final class AIPluginLanguageModelProvider: ExtensionLanguageModelProviding {

    /// Separates the configuration UUID from the model name inside a
    /// descriptor id. A UUID never contains one, which is what makes the
    /// first-separator split unambiguous.
    private static let idSeparator: Character = "/"

    /// What a request can fail on before a plugin is ever reached.
    public enum ProviderError: Error, Equatable, CustomStringConvertible {

        /// The descriptor id did not parse, or named a configuration that is
        /// no longer in `UserSettings.aiProviderConfigurations`. Both are the
        /// same event from an extension's point of view: it held a model
        /// descriptor across the user deleting the provider behind it.
        case unknownModel(String)

        /// The configuration resolved, but its plugin could not be loaded —
        /// an uninstalled `.aiplugin`, or a template id the descriptor no
        /// longer declares (`AIProviderResolver.resolve` fails closed on that
        /// second one, deliberately, and this carries the failure through).
        case pluginUnavailable(String)

        public var description: String {
            switch self {
            case .unknownModel(let id):
                return "no configured language model with id '\(id)'"
            case .pluginUnavailable(let identifier):
                return "the plugin '\(identifier)' is not available"
            }
        }
    }

    private let pluginManager: AIPluginManager

    /// Fires when the configured provider list changes, so
    /// `MainThreadLanguageModels.availableChatModelsDidChange()` can be
    /// called and `vscode.lm.onDidChangeChatModels` published.
    ///
    /// A closure the host wires rather than a direct reference to the
    /// adaptors: there is one provider and one adaptor *per extension*, so
    /// this type must not know how many there are or hold them alive.
    /// Publishing is debounced by identity one layer up (Ruling 63), so
    /// firing this on a settings write that changed nothing relevant costs
    /// nothing.
    public var onAvailableChatModelsChanged: (() -> Void)?

    private var configurationsObserver: UserSettingObserver<[AIProviderConfiguration]>?

    public init(pluginManager: AIPluginManager) {
        self.pluginManager = pluginManager
        configurationsObserver = UserSettingObserver(
            UserSettings.aiProviderConfigurations
        ) { [weak self] _ in
            self?.onAvailableChatModelsChanged?()
        }
    }

    // MARK: - ExtensionLanguageModelProviding

    /// Every model of every configured provider, ordered by the
    /// configuration order the user sees in settings and then by the
    /// template's own model order — deterministic, as the protocol requires,
    /// and the same order twice running because both lists are stored
    /// sequences rather than sets.
    ///
    /// A configuration whose template no longer resolves contributes nothing
    /// instead of contributing a half-formed descriptor: `AIProviderResolver`
    /// fails closed on exactly that case and says why, and a model an
    /// extension cannot actually send to is worse than one it never saw.
    public var availableChatModels: [LanguageModelChatDescriptor] {
        var descriptors: [LanguageModelChatDescriptor] = []
        for configuration in UserSettings.aiProviderConfigurations.currentValue {
            guard let template = pluginManager.template(
                pluginIdentifier: configuration.pluginIdentifier,
                templateId: configuration.templateId
            ) else { continue }

            for model in template.models {
                descriptors.append(
                    Self.descriptor(for: model, configuration: configuration, template: template))
            }
        }
        return descriptors
    }

    public func streamResponse(
        for model: LanguageModelChatDescriptor,
        messages: [ExtensionLanguageModelMessage],
        justification: String?,
        extensionIdentifier: String
    ) async throws -> AsyncThrowingStream<ExtensionLanguageModelResponsePart, Error> {

        // Ledger Ruling 4: this host implements no consent gate, so nothing
        // interprets `justification` — it is recorded and no further. Logged
        // rather than dropped because it is the only trace that an extension
        // said why it wanted a model, and the gate that will one day read it
        // has to be able to see what extensions actually send.
        if let justification {
            Self.logger.info(
                """
                extension \(extensionIdentifier, privacy: .public) requested a language \
                model, justification: \(justification, privacy: .private)
                """)
        }

        let (configuration, modelName) = try resolveConfiguration(for: model)
        guard let resolved = AIProviderResolver.resolve(configuration, manager: pluginManager) else {
            throw ProviderError.pluginUnavailable(configuration.pluginIdentifier)
        }
        guard let plugin = try? pluginManager.loadPlugin(identifier: resolved.pluginIdentifier) else {
            throw ProviderError.pluginUnavailable(resolved.pluginIdentifier)
        }

        // `resolved.values` carries the configuration's *own* selected model
        // under "model" (`AIProviderConfigStore.configValues`), which is the
        // app's chat choice. The extension picked a model by descriptor, and
        // that is the one the request must use — so both the bag and the
        // context's `model` are overridden here, together, because a plugin
        // may read either.
        var values = resolved.values
        values["model"] = modelName

        let context = AIChatContext(
            messages: messages.map(Self.chatMessage(for:)),
            model: modelName,
            systemPrompt: nil,
            // Ruling 54 keeps `tools` and `toolMode` at the adaptor, recorded
            // into the not-implemented ledger, so nothing arrives here to
            // pass on — an empty list is the truth, not a placeholder.
            tools: [],
            config: AIPluginConfig(values)
        )

        let spec = try plugin.buildRequest(context)
        let source = PluginTransport.run(spec: spec, plugin: plugin)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in source {
                        continuation.yield(Self.responsePart(for: event))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // The seam's stream is single-consumption and the consumer may
            // stop early — a cancelled `sendRequest` token does exactly that
            // — so terminating it has to reach the transport rather than
            // leaving an HTTP response draining into a finished continuation.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Descriptors

    private static func descriptor(
        for model: String,
        configuration: AIProviderConfiguration,
        template: AIPluginDescriptor.ProviderTemplate
    ) -> LanguageModelChatDescriptor {
        let catalog = AIModelCatalog.shared.resolve(model: model, template: template)
        return LanguageModelChatDescriptor(
            // The user named the configuration, and a window listing four
            // OpenAI-compatible gateways is the case that name exists for —
            // so the descriptor's display name carries it alongside the
            // model rather than showing four identically-named models.
            name: "\(configuration.name) · \(model)",
            id: "\(configuration.id.uuidString)\(idSeparator)\(model)",
            // `vendor` is who serves the model; `family` is what the model
            // *is*. `template.provider` is documented as the former
            // ("Anthropic", "Groq") and falls back to the template's display
            // name, and `canonicalID` is this repo's existing answer to the
            // latter — the same normalisation the model catalog indexes on,
            // so two gateways serving one model report one family.
            vendor: template.provider ?? template.displayName,
            family: AIModelCatalog.canonicalID(model),
            version: model,
            maxInputTokens: catalog.contextWindow ?? defaultMaxInputTokens
        )
    }

    /// What `maxInputTokens` reports for a model the shipped catalog has no
    /// context window for — 11 of the 793 offerings it ships, plus any model
    /// a gateway added after the catalog was generated.
    ///
    /// **4096, and deliberately not a guess at the real figure.** It is the
    /// number `AIChatContext.init` already defaults `maxTokens` to, which is
    /// this repo's existing answer to "a model whose limits we do not know",
    /// so the unknown case reports a bound the codebase already stands
    /// behind rather than one invented here. It under-reports every model it
    /// applies to, and that is the safe direction: an extension that trims a
    /// prompt to fit 4096 tokens is never rejected for length, where an
    /// optimistic figure would produce a provider-side failure the extension
    /// has no way to anticipate.
    private static let defaultMaxInputTokens = 4096

    /// The configuration and model name behind a descriptor the seam handed
    /// back. Re-read from settings rather than captured when the descriptor
    /// was built: an extension may hold a descriptor for as long as it likes,
    /// and what the user has configured *now* is what a request can actually
    /// reach.
    private func resolveConfiguration(
        for model: LanguageModelChatDescriptor
    ) throws -> (AIProviderConfiguration, String) {
        guard let separator = model.id.firstIndex(of: Self.idSeparator) else {
            throw ProviderError.unknownModel(model.id)
        }
        let identifier = String(model.id[model.id.startIndex..<separator])
        let modelName = String(model.id[model.id.index(after: separator)...])
        guard let uuid = UUID(uuidString: identifier),
              let configuration = UserSettings.aiProviderConfigurations.currentValue
                  .first(where: { $0.id == uuid })
        else {
            throw ProviderError.unknownModel(model.id)
        }
        return (configuration, modelName)
    }

    // MARK: - Mapping

    private static func chatMessage(for message: ExtensionLanguageModelMessage) -> AIChatMessage {
        // `ExtensionLanguageModelMessage.name` is `LanguageModelChatMessage
        // .name` (`vscode.d.ts`), which `AIChatMessage` has no field for —
        // its `toolName` is a different thing entirely, and putting one in
        // the other would make a plain user message look like a tool result.
        // Dropped rather than misfiled.
        AIChatMessage(
            role: message.role == .user ? .user : .assistant,
            content: message.text
        )
    }

    /// The 1:1 map `ExtensionLanguageModelResponsePart`'s own doc specifies —
    /// three cases there, three here, nothing lost and nothing invented.
    private static func responsePart(for event: AIStreamEvent) -> ExtensionLanguageModelResponsePart {
        switch event {
        case .textDelta(let text):
            return .text(text)
        case .toolUse(let id, let name, let argumentsJSON):
            return .toolCall(id: id, name: name, argumentsJSON: argumentsJSON)
        case .end(let stopReason):
            return .end(stopReason: stopReason)
        }
    }
}

extension AIPluginLanguageModelProvider: Loggable {
    public static nonisolated let logger = makeLogger()
}
