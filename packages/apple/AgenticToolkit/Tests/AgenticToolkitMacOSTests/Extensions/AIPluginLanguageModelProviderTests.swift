//
//  AIPluginLanguageModelProviderTests.swift
//  AgenticToolkitMacOSTests
//

import Foundation
import Testing
@testable import AIPluginKit
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// `AIPluginLanguageModelProvider`, the production `ExtensionLanguageModelProviding`
/// that lists the user's configured AI providers as `vscode.lm` models.
///
/// This suite writes directly to `UserSettings.aiProviderConfigurations.value`
/// against the real, ambient `UserSettings.shared`, the same way
/// `LLMProvidersListViewModelTests` does — **not** `withInMemorySettings`.
/// `UserSettings.aiProviderConfigurations` is declared `static let`, and a
/// `UserSetting` permanently subscribes to whichever `UserSettings.shared` was
/// live the first time that static was touched; swapping `UserSettings.shared`
/// inside this suite would write to a store the setting's change publisher can
/// never see fire, and `onAvailableChatModelsChanged` would never call back.
@Suite("AIPluginLanguageModelProvider")
@MainActor
struct AIPluginLanguageModelProviderTests {

    // MARK: - Fixtures

    /// Matches `LLMProvidersListViewModelTests.reset()`: both settings this
    /// type reads are reset to empty before every test, so one test's
    /// configurations can never leak into the next.
    private func reset() {
        UserSettings.aiProviderConfigurations.value = []
        UserSettings.selectedAIProviderConfigurationId.value = ""
    }

    /// A plugin manager carrying one descriptor, registered with
    /// `registerForTesting` so no `.aiplugin` bundle has to exist on disk —
    /// this suite never reaches `loadPlugin`'s happy path, only the
    /// descriptor-only reads `availableChatModels` and `AIProviderResolver`
    /// use.
    private func manager(
        pluginIdentifier: String = "test.plugin",
        templateId: String = "template-a",
        models: [String] = ["model-a", "model-b"]
    ) -> AIPluginManager {
        let pluginManager = AIPluginManager(searchPaths: [], appName: "Test")
        pluginManager.registerForTesting(AIPluginDescriptor(
            schemaVersion: 3,
            identifier: pluginIdentifier,
            displayName: "Test Plugin",
            version: "1.0",
            templates: [.init(id: templateId, displayName: "Template A", models: models)]
        ))
        return pluginManager
    }

    /// A continuation-based hop to the next main-queue turn, matching
    /// `ExternalThemeChangeObservationTests.drain()`: `UserSettingObserver`
    /// delivers `onChange` via `.receive(on: DispatchQueue.main)`, so a
    /// synchronous assertion right after the write would race the callback.
    private func drain() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    // MARK: - availableChatModels

    @Test("availableChatModels exposes every model of every configured provider")
    func availableChatModelsExposesEveryModelOfEveryConfiguredProvider() {
        reset()
        let pluginManager = manager(models: ["model-a", "model-b"])
        let configuration = AIProviderConfiguration(
            name: "My Provider", pluginIdentifier: "test.plugin", templateId: "template-a")
        UserSettings.aiProviderConfigurations.value = [configuration]

        let provider = AIPluginLanguageModelProvider(pluginManager: pluginManager)
        let models = provider.availableChatModels

        #expect(models.map(\.id) == [
            "\(configuration.id.uuidString)/model-a",
            "\(configuration.id.uuidString)/model-b"
        ])
        #expect(models.map(\.name) == ["My Provider · model-a", "My Provider · model-b"])
        #expect(models.allSatisfy { $0.vendor == "Template A" })
        #expect(models.map(\.family) == ["model-a", "model-b"])
        #expect(models.map(\.version) == ["model-a", "model-b"])
        // Neither fake model appears in the shipped catalog's offerings under
        // this made-up template id, so both fall back to the documented
        // "unknown model" bound rather than a real context window.
        #expect(models.allSatisfy { $0.maxInputTokens == 4096 })
    }

    /// A configuration whose plugin was never registered, or whose
    /// `templateId` the descriptor no longer declares, contributes nothing —
    /// `pluginManager.template(pluginIdentifier:templateId:)` returns `nil`
    /// and `availableChatModels`'s own doc says a half-formed descriptor is
    /// worse than a missing one.
    @Test("a configuration whose plugin is unregistered contributes no models")
    func aConfigurationWhosePluginIsUnregisteredContributesNoModels() {
        reset()
        // No `registerForTesting` call at all — the manager knows no plugins.
        let pluginManager = AIPluginManager(searchPaths: [], appName: "Test")
        UserSettings.aiProviderConfigurations.value = [
            AIProviderConfiguration(
                name: "Orphaned", pluginIdentifier: "never.registered", templateId: "template-a")
        ]

        let provider = AIPluginLanguageModelProvider(pluginManager: pluginManager)

        #expect(provider.availableChatModels.isEmpty)
    }

    /// The cross product across two configurations, in configuration order
    /// then template model order — `availableChatModels`'s own doc names
    /// this as the whole point of listing "every configured provider" rather
    /// than the app's single selected one.
    @Test("availableChatModels orders by configuration order, then by the template's model order")
    func availableChatModelsOrdersByConfigurationThenModelOrder() {
        reset()
        let pluginManager = manager(models: ["only-model"])
        let first = AIProviderConfiguration(
            name: "First", pluginIdentifier: "test.plugin", templateId: "template-a")
        let second = AIProviderConfiguration(
            name: "Second", pluginIdentifier: "test.plugin", templateId: "template-a")
        UserSettings.aiProviderConfigurations.value = [first, second]

        let provider = AIPluginLanguageModelProvider(pluginManager: pluginManager)

        #expect(provider.availableChatModels.map(\.name) == [
            "First · only-model", "Second · only-model"
        ])
    }

    // MARK: - onAvailableChatModelsChanged

    /// The behaviour the seven-item brief calls out by name: a write to
    /// `UserSettings.aiProviderConfigurations` must fire
    /// `onAvailableChatModelsChanged`, which is what lets
    /// `MainThreadLanguageModels.availableChatModelsDidChange()` publish
    /// `vscode.lm.onDidChangeChatModels`. Pinned end to end through the real
    /// `UserSetting`/`UserSettingObserver` publisher chain, not a fake.
    @Test("onAvailableChatModelsChanged fires when the configured provider list changes")
    func onAvailableChatModelsChangedFiresWhenTheConfiguredProviderListChanges() async {
        reset()
        let pluginManager = manager()
        let provider = AIPluginLanguageModelProvider(pluginManager: pluginManager)

        var fireCount = 0
        provider.onAvailableChatModelsChanged = { fireCount += 1 }

        UserSettings.aiProviderConfigurations.value = [
            AIProviderConfiguration(
                name: "New", pluginIdentifier: "test.plugin", templateId: "template-a")
        ]
        await drain()

        #expect(fireCount == 1)
    }

    /// Constructing the provider must not itself fire the callback — only a
    /// genuine *change* should, matching `UserSettingObserver`'s own
    /// `.dropFirst()` on its underlying publisher.
    @Test("constructing the provider does not fire onAvailableChatModelsChanged")
    func constructingTheProviderDoesNotFireOnAvailableChatModelsChanged() async {
        reset()
        UserSettings.aiProviderConfigurations.value = [
            AIProviderConfiguration(
                name: "Existing", pluginIdentifier: "test.plugin", templateId: "template-a")
        ]
        let pluginManager = manager()
        let provider = AIPluginLanguageModelProvider(pluginManager: pluginManager)

        var fireCount = 0
        provider.onAvailableChatModelsChanged = { fireCount += 1 }
        await drain()

        #expect(fireCount == 0)
    }

    // MARK: - streamResponse error paths

    /// A descriptor id with no `/` separator never named a configuration at
    /// all — `resolveConfiguration`'s first guard, thrown before any plugin
    /// is touched.
    @Test("streamResponse throws unknownModel for a descriptor id with no separator")
    func streamResponseThrowsUnknownModelForADescriptorIDWithNoSeparator() async {
        reset()
        let provider = AIPluginLanguageModelProvider(pluginManager: manager())
        let model = LanguageModelChatDescriptor(
            name: "bad", id: "not-a-uuid-slash-model", vendor: "v", family: "f",
            version: "1", maxInputTokens: 4096)

        await #expect(throws: AIPluginLanguageModelProvider.ProviderError.unknownModel(model.id)) {
            _ = try await provider.streamResponse(
                for: model, messages: [], justification: nil, extensionIdentifier: "test.ext")
        }
    }

    /// A descriptor id that parses but names a configuration the user has
    /// since deleted — `resolveConfiguration`'s second guard.
    @Test("streamResponse throws unknownModel for a configuration id no longer in settings")
    func streamResponseThrowsUnknownModelForAConfigurationIDNoLongerInSettings() async {
        reset()
        let provider = AIPluginLanguageModelProvider(pluginManager: manager())
        let deletedID = UUID().uuidString
        let model = LanguageModelChatDescriptor(
            name: "bad", id: "\(deletedID)/model-a", vendor: "v", family: "f",
            version: "1", maxInputTokens: 4096)

        await #expect(throws: AIPluginLanguageModelProvider.ProviderError.unknownModel(model.id)) {
            _ = try await provider.streamResponse(
                for: model, messages: [], justification: nil, extensionIdentifier: "test.ext")
        }
    }

    /// A configuration whose plugin was never registered: `AIProviderResolver
    /// .resolve` returns `nil` because `manager.descriptor(for:)` finds
    /// nothing, and `streamResponse` turns that into `.pluginUnavailable`
    /// carrying the configuration's own plugin identifier.
    @Test("streamResponse throws pluginUnavailable when the configuration's plugin is unregistered")
    func streamResponseThrowsPluginUnavailableWhenThePluginIsUnregistered() async {
        reset()
        // A manager with no plugins registered at all.
        let pluginManager = AIPluginManager(searchPaths: [], appName: "Test")
        let provider = AIPluginLanguageModelProvider(pluginManager: pluginManager)
        let configuration = AIProviderConfiguration(
            name: "Orphaned", pluginIdentifier: "never.registered", templateId: "template-a")
        UserSettings.aiProviderConfigurations.value = [configuration]
        let model = LanguageModelChatDescriptor(
            name: "bad", id: "\(configuration.id.uuidString)/model-a", vendor: "v", family: "f",
            version: "1", maxInputTokens: 4096)

        await #expect(throws: AIPluginLanguageModelProvider.ProviderError.pluginUnavailable(
            configuration.pluginIdentifier
        )) {
            _ = try await provider.streamResponse(
                for: model, messages: [], justification: nil, extensionIdentifier: "test.ext")
        }
    }
}
