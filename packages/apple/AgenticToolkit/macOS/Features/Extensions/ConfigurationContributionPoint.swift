//
//  ConfigurationContributionPoint.swift
//  AgenticToolkit
//

import AppKit
import AgenticToolkitCore
import Foundation

/// Registers what each extension's `contributes.configuration` declares, and
/// builds a settings panel over it on demand.
///
/// The classification — what row a schema deserves, where its value lives —
/// is `ContributedSettingsBuilder`'s, in `apple-core`, where it can be tested
/// without a window. This class is the AppKit half only: it remembers what was
/// applied, and turns it into views.
@MainActor
public final class ConfigurationContributionPoint: ContributionPoint {

    private struct Registration {
        let identifier: String
        /// `displayName ?? name`, kept for the panel's title. Reading it back
        /// off the manifest at `panel(for:)` time would mean holding the
        /// manifest, and the manifest is the one thing here that is allowed to
        /// have gone away.
        let title: String
        let declaration: ContributedSettingsDeclaration
    }

    /// An array, not a dictionary: `contributingExtensions` is specified in
    /// registration order, and a dictionary has no order to report.
    private var registrations: [Registration] = []

    /// Every compromise made while classifying, across every applied
    /// extension, in application order.
    public private(set) var notes: [ContributedSettingNote] = []

    public init() {}

    public var contributionKey: String { "configuration" }

    /// - Parameter directory: unused, and named `_` for that reason. A
    ///   `configuration` contribution is a schema written inline in
    ///   `package.json`; it names no file, so this point opens none.
    ///
    ///   Should that ever change, resolve a manifest-relative path as
    ///   `URL(fileURLWithPath: directory.path, isDirectory: true)` first:
    ///   `URL(fileURLWithPath:relativeTo:)` resolves against the base's
    ///   *parent* unless the base is known to be a directory, and Task 4.5a
    ///   shipped that bug once already.
    public func apply(
        _ contributions: ExtensionManifest.Contributions,
        from manifest: ExtensionManifest,
        at _: URL
    ) throws {
        // Withdraw first, as every contribution point here does: applying the
        // same extension twice — a reload, a disable/enable — must leave one
        // copy, and this class does not get to depend on the registry
        // withdrawing before it reloads.
        withdraw(extensionIdentifier: manifest.identifier)

        let built = ContributedSettingsBuilder.sections(
            for: contributions.configuration,
            ofExtension: manifest.identifier,
            fallbackTitle: manifest.displayName ?? manifest.name
        )
        // An extension that declared no `configuration` at all is not
        // registered: `declaration(for:)` answers `.undeclared` for an
        // identifier it has never heard of, which is the same true sentence.
        guard case .declared = built.declaration else { return }

        registrations.append(Registration(
            identifier: manifest.identifier,
            title: manifest.displayName ?? manifest.name,
            declaration: built.declaration
        ))
        notes.append(contentsOf: built.notes)
    }

    /// Unregisters an extension's sections and its notes.
    ///
    /// Deliberately does not call `UserSetting.remove()`. A user who disables
    /// an extension for an afternoon, or reinstalls it after an update, has
    /// not asked for the values they typed to be forgotten — and VS Code does
    /// not forget them either. The rows go; what they held stays.
    public func withdraw(extensionIdentifier: String) {
        registrations.removeAll { $0.identifier == extensionIdentifier }
        notes.removeAll { $0.extensionIdentifier == extensionIdentifier }
    }

    /// Identifiers with at least one section, in registration order.
    public var contributingExtensions: [String] {
        registrations.filter { !$0.declaration.sections.isEmpty }.map(\.identifier)
    }

    public func sections(for extensionIdentifier: String) -> [ContributedSettingsSection] {
        declaration(for: extensionIdentifier).sections
    }

    /// What this extension had to say about settings — including the
    /// difference between saying nothing and saying something that rendered as
    /// nothing, which `sections(for:)` flattens into the same empty array.
    public func declaration(for extensionIdentifier: String) -> ContributedSettingsDeclaration {
        registrations.first { $0.identifier == extensionIdentifier }?.declaration ?? .undeclared
    }

    /// A panel over the registered sections, or `nil` when this extension
    /// contributed no section to show. Task 4.6 presents these; nothing here
    /// does.
    public func panel(
        for extensionIdentifier: String
    ) -> ComposableSettings.SettingsPanelViewController? {
        guard let registration = registrations.first(where: { $0.identifier == extensionIdentifier }),
              !registration.declaration.sections.isEmpty else {
            return nil
        }

        let sections = registration.declaration.sections
        let panel = GeneratedSettingsPanel(
            descriptor: ComposableSettings.SettingsPanelDescriptor(title: registration.title),
            // The keys, because the sidebar's search runs over panels it has
            // not built, and a generated panel has no labels to read until it
            // is. Already in the order the rows are in.
            searchKeys: sections.flatMap { $0.settings.map(\.key) }
        )

        // Rows are built eagerly, the panel lazily. The largest section in the
        // corpus holds 186 properties — one card of 186 rows, built once when
        // someone opens that extension — which is not worth a cache that would
        // then have to be invalidated on every re-apply.
        for section in sections {
            let group = ComposableSettings.GroupView(withTitle: section.title)
            for setting in section.settings {
                group.addSettingSubview(row(for: setting))
                if let explanation = setting.explanation, !explanation.isEmpty {
                    // `.continuation` so the prose reads as part of the row
                    // above it rather than as a row of its own.
                    group.addSettingSubview(
                        ComposableSettings.ExplanationView(withText: explanation),
                        style: .continuation)
                }
            }
            panel.addGroup(group)
        }
        return panel
    }

    // MARK: - Rows

    private func row(for setting: ContributedSetting) -> NSView {
        switch setting.kind {
        case .toggle(let value):
            return ComposableSettings.CheckboxView(with: ComposableSettings.ViewModel(
                title: setting.key,
                setting: UserSetting(setting.storageName, default: value)))

        case .text(let value, let multiline):
            let viewModel = ComposableSettings.ViewModel(
                title: setting.key,
                setting: UserSetting(setting.storageName, default: value))
            return multiline
                ? ComposableSettings.TextAreaEditView(with: viewModel)
                : ComposableSettings.TextEditView(with: viewModel)

        case .choice(let options, let value):
            return ComposableSettings.PopupMenuChoiceView(
                viewModel: ComposableSettings.ChoiceViewModel(
                    title: setting.key,
                    setting: UserSetting(setting.storageName, default: value),
                    choices: options.map { .init(label: $0.label, value: $0.value) }))

        case .number(let value, let minimum, let maximum):
            return ComposableSettings.NumberFieldView(
                viewModel: ComposableSettings.ViewModel(
                    title: setting.key,
                    setting: UserSetting(setting.storageName, default: value)),
                minimum: minimum,
                maximum: maximum)

        case .integer(let value, let minimum, let maximum):
            return ComposableSettings.NumberFieldView(
                viewModel: ComposableSettings.ViewModel(
                    title: setting.key,
                    setting: UserSetting(setting.storageName, default: value)),
                minimum: minimum,
                maximum: maximum)

        case .json(let text):
            return JSONTextAreaEditView(with: ComposableSettings.ViewModel(
                title: setting.key,
                setting: UserSetting(setting.storageName, default: text)))
        }
    }
}

/// A panel that answers the sidebar's search with the keys it was generated
/// from.
///
/// A subclass only because `searchKeywords` is an override point rather than a
/// stored property; it adds nothing else.
@MainActor
private final class GeneratedSettingsPanel: ComposableSettings.SettingsPanelViewController {

    private let searchKeys: [String]

    init(descriptor: ComposableSettings.SettingsPanelDescriptor, searchKeys: [String]) {
        self.searchKeys = searchKeys
        super.init(with: descriptor)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var searchKeywords: [String] { searchKeys }
}

/// The escape hatch's editor: a monospaced text area that refuses to store
/// text that is not JSON.
///
/// Refuses rather than stores, because the value's *only* consumer parses it.
/// Text that does not parse is not a setting with an unusual value; it is a
/// setting with no value at all, and storing it would replace a working
/// default with something the extension cannot read.
///
/// Internal rather than private so a test can drive a commit through the view
/// the panel actually built: counting `TextAreaEditView` descendants cannot
/// tell this class from its superclass, so with it private the validation
/// could be deleted outright and the suite would stay green.
@MainActor
final class JSONTextAreaEditView: ComposableSettings.TextAreaEditView {

    /// Held again here — the superclass's is private — so an invalid edit has
    /// something to revert to.
    private let jsonViewModel: ComposableSettings.ViewModel<String>

    init(with viewModel: ComposableSettings.ViewModel<String>) {
        self.jsonViewModel = viewModel
        super.init(with: viewModel, visibleLines: 6, monospaced: true)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func commit() {
        // `.fragmentsAllowed`: a contributed default is as often `3` or
        // `"auto"` as it is an object, and a parser that called those invalid
        // would reject the text it was just given.
        guard let data = textView.string.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else {
            textView.string = jsonViewModel.value
            return
        }
        super.commit()
    }
}
