import SwiftUI
import CodeEditLanguages

import AgenticToolkitCore
import AgenticToolkitCoreMacOS

// MARK: - Custom File Type Mapping Model

/// A user-defined mapping from a file extension to a language name and icon.
///
/// Custom mappings take precedence over the built-in CodeEditLanguages
/// detection, allowing users to override or extend file type associations.
public struct CustomFileTypeMapping: Codable, Identifiable, Equatable, Sendable {
    public var id: String { fileExtension }

    /// The file extension without the leading dot (e.g., "tsx", "conf").
    public let fileExtension: String

    /// The display name for this language (e.g., "TypeScript React").
    public var languageName: String

    /// The SF Symbol name for the file icon (e.g., "doc.text", "swift").
    public var iconName: String

    public init(fileExtension: String, languageName: String, iconName: String) {
        self.fileExtension = fileExtension
        self.languageName = languageName
        self.iconName = iconName
    }
}

// MARK: - Custom Mappings Store

/// Manages persistence and lookup for user-defined file type mappings.
///
/// Mappings are stored as JSON in UserDefaults and consulted before
/// the built-in `CodeEditLanguages` detection. A cached lookup dictionary
/// avoids repeated JSON decoding on every file icon resolution.
///
/// The UserDefaults key is configurable via `activeDefaultsKey`. Host
/// applications should set this once at startup (typically from their
/// `FileTreeConfig.customMappingsDefaultsKey`) before any UI consults the
/// mappings. Reading call sites that don't carry a `FileTreeConfig`
/// (e.g., `FileTreeNode.fileIconName`) rely on this static.
public enum CustomFileTypeMappings {

    /// The UserDefaults key used by `load` / `save` / `mapping(for:)`.
    /// Host apps override this at startup from their `FileTreeConfig`.
    nonisolated(unsafe) public static var activeDefaultsKey: String = FileTreeConfig.default.customMappingsDefaultsKey

    /// Cached lookup dictionary keyed by lowercased extension.
    /// Invalidated when `save` is called.
    nonisolated(unsafe) private static var cache: [String: CustomFileTypeMapping]?

    /// Consulted when the user's own mappings do not claim an extension, so a
    /// user mapping always outranks one an installed extension contributed.
    /// Set by the host once at startup, the same way `activeDefaultsKey` is —
    /// see `LanguageContributionPoint.install()`.
    ///
    /// Contributed mappings deliberately do not go through `save`: that array
    /// is persisted in UserDefaults, outlives the extension that wrote into
    /// it, and is the exact array `FileTypesSettingsView` presents as the
    /// user's own editable rows.
    nonisolated(unsafe) public static var contributedProvider: (@Sendable (String) -> CustomFileTypeMapping?)?

    /// Loads custom mappings from UserDefaults.
    public static func load() -> [CustomFileTypeMapping] {
        guard let data = UserDefaults.standard.data(forKey: activeDefaultsKey) else {
            return []
        }
        return (try? JSONDecoder().decode([CustomFileTypeMapping].self, from: data)) ?? []
    }

    /// Saves custom mappings to UserDefaults and invalidates the lookup cache.
    public static func save(_ mappings: [CustomFileTypeMapping]) {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        UserDefaults.standard.set(data, forKey: activeDefaultsKey)
        cache = nil
    }

    /// Returns the custom mapping for a file extension, if one exists.
    ///
    /// Uses a cached dictionary for fast lookups during file tree rendering,
    /// avoiding repeated JSON decoding from UserDefaults.
    ///
    /// Falls through to `contributedProvider` only when the user's own
    /// mappings do not claim the extension: precedence is user > extension >
    /// built-in, the one order in which an installed extension cannot
    /// silently change a mapping the user typed themselves. The provider is
    /// handed the already-lowercased key, and is never asked about the empty
    /// string — both call sites guard on that.
    public static func mapping(for fileExtension: String) -> CustomFileTypeMapping? {
        if cache == nil {
            let mappings = load()
            // `uniquingKeysWith:`, not `uniqueKeysWithValues:`, which traps on
            // a duplicate key. The settings UI permits two rows whose
            // extensions differ only in case — `CustomFileTypeMapping.id` is
            // the raw string, so "MD" and "md" are two distinct rows to
            // SwiftUI — and lowercasing here collides them. First wins, so the
            // behaviour matches the order the user sees in the list.
            cache = Dictionary(
                mappings.map { ($0.fileExtension.lowercased(), $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        let key = fileExtension.lowercased()
        return cache?[key] ?? contributedProvider?(key)
    }
}

// MARK: - Built-in File Type Icons

/// The extension→SF Symbol table the file browser draws from.
///
/// One table, three readers: the file tree (`FileTreeNode.fileIconName`), the
/// settings panel's built-in rows (`BuiltInFileType.allBuiltIn`) and the
/// mappings an extension contributes (`LanguageContributionPoint`). It was two
/// copies until the third reader arrived, and they had already drifted — the
/// tree's copy did not know `mkd`, `mjs` or `shtml` — which is the whole
/// argument for it being one.
///
/// Returns `nil` rather than a fallback for an extension it does not know:
/// each reader's fallback is its own. The tree and the settings list want a
/// blank `doc`; a contributed mapping wants `doc.text`, because it is
/// *replacing* a built-in row rather than being one.
public enum FileTypeIcons {

    /// The SF Symbol for a file extension, or `nil` if there is no better
    /// answer than the caller's default. `fileExtension` may be in any case.
    public static func builtInIcon(for fileExtension: String) -> String? {
        switch fileExtension.lowercased() {
        case "swift":
            return "swift"
        case "json":
            return "curlybraces"
        case "md", "markdown", "mkd", "mkdn", "mdwn", "mdown":
            return "doc.richtext"
        case "txt", "text":
            return "doc.text"
        case "plist":
            return "list.bullet.rectangle"
        case "xcodeproj", "xcworkspace":
            return "hammer.fill"
        case "entitlements":
            return "lock.shield"
        case "png", "jpg", "jpeg", "gif", "svg", "ico":
            return "photo"
        case "yaml", "yml", "toml":
            return "gearshape.2"
        case "sh", "zsh", "bash":
            return "terminal"
        case "py":
            return "chevron.left.forwardslash.chevron.right"
        case "js", "ts", "cjs", "mjs", "cts", "mts":
            return "chevron.left.forwardslash.chevron.right"
        case "css", "html", "htm", "shtml":
            return "globe"
        case "gitignore":
            return "eye.slash"
        default:
            return nil
        }
    }
}

// MARK: - Built-in File Type Entry

/// A read-only display entry for a built-in language from CodeEditLanguages.
private struct BuiltInFileType: Identifiable {
    public let id: String
    public let fileExtension: String
    public let languageName: String
    public let iconName: String

    /// Derives built-in entries from CodeEditLanguages definitions.
    public static func allBuiltIn() -> [BuiltInFileType] {
        var entries: [BuiltInFileType] = []
        for lang in CodeLanguage.allLanguages {
            for ext in lang.extensions.sorted() {
                // Skip empty extensions and internal languages
                guard !ext.isEmpty else { continue }
                entries.append(BuiltInFileType(
                    // The language belongs in the id: several languages claim
                    // the same extension (`.h`, `.m`, `.ts`), and an id shared
                    // by two rows makes `ForEach` render one of them twice.
                    id: "builtin-\(lang.tsName)-\(ext)",
                    fileExtension: ext,
                    languageName: lang.tsName.capitalized,
                    iconName: FileTypeIcons.builtInIcon(for: ext) ?? "doc"
                ))
            }
        }
        return entries.sorted {
            $0.fileExtension.localizedCaseInsensitiveCompare($1.fileExtension) == .orderedAscending
        }
    }
}

// MARK: - File Types Settings View

/// Settings tab for viewing built-in file type associations and adding custom ones.
///
/// Shows every recognized file extension with its language name and icon. Users
/// can add custom mappings that override the built-in detection.
///
/// Laid out with `ComposableSettings`' card vocabulary rather than a `List`, so
/// it reads as the same kind of thing as every other panel in the window. A
/// `List` gave it striped rows under a sticky grey section header, which is a
/// perfectly good table and looks nothing like the rest of the settings window.
public struct FileTypesSettingsView: View {

    // MARK: - State

    @Environment(\.theme) private var theme

    @State private var customMappings: [CustomFileTypeMapping] = CustomFileTypeMappings.load()
    @State private var builtInTypes: [BuiltInFileType] = BuiltInFileType.allBuiltIn()
    @State private var showingAddSheet = false
    @State private var searchText = ""

    public init() {}

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Above the scroll, so it stays put while a few hundred extensions
            // go by, and leading-aligned so it clears the help button in the
            // panel's top-right corner.
            ComposableSettings.SettingsSearchField("Search file types", text: $searchText)
                .frame(maxWidth: 240)
                .padding(.horizontal, ComposableSettings.SettingsLayout.default[.panelInset])
                .padding(.top, ComposableSettings.SettingsLayout.default[.panelInset])

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: ComposableSettings.SettingsLayout.default[.groupSpacing]
                ) {
                    customGroup
                    builtInGroup
                }
                .padding(.horizontal, ComposableSettings.SettingsLayout.default[.panelInset])
                .padding(.vertical, ComposableSettings.SettingsLayout.default[.groupSpacing])
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingAddSheet) {
            AddCustomFileTypeSheet(
                existingExtensions: Set(customMappings.map { $0.fileExtension.lowercased() }),
                onSave: { mapping in
                    addCustomMapping(mapping)
                }
            )
        }
    }

    // MARK: - Groups

    private var customGroup: some View {
        ComposableSettings.SettingsGroup("Custom Mappings") {
            if filteredCustomMappings.isEmpty {
                ComposableSettings.SettingsCardRow {
                    Text(customMappings.isEmpty
                        ? "No custom types yet: the built-in list below is what the editor uses."
                        : "No custom type matches the search.")
                        .font(theme.font(.caption))
                        .foregroundStyle(theme.secondaryText)
                }
            } else {
                ForEach(
                    Array(filteredCustomMappings.enumerated()), id: \.element.id
                ) { index, mapping in
                    if index > 0 {
                        ComposableSettings.SettingsCardDivider()
                    }
                    ComposableSettings.SettingsCardRow {
                        FileTypeRow(
                            fileExtension: mapping.fileExtension,
                            languageName: mapping.languageName,
                            iconName: mapping.iconName,
                            isCustom: true,
                            onRemove: { removeCustomMapping(mapping) }
                        )
                    }
                }
            }

            // The card's own action row, where System Settings puts its "+".
            ComposableSettings.SettingsCardDivider()
            ComposableSettings.SettingsCardRow {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Custom Type", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var builtInGroup: some View {
        ComposableSettings.SettingsGroup("Built-in Types (\(filteredBuiltInTypes.count))") {
            if filteredBuiltInTypes.isEmpty {
                ComposableSettings.SettingsCardRow {
                    Text("No built-in type matches the search.")
                        .font(theme.font(.caption))
                        .foregroundStyle(theme.secondaryText)
                }
            } else {
                // Lazy because the built-in list is every extension the editor
                // knows, and only a screenful of it is ever on screen.
                LazyVStack(spacing: 0) {
                    ForEach(
                        Array(filteredBuiltInTypes.enumerated()), id: \.element.id
                    ) { index, entry in
                        if index > 0 {
                            ComposableSettings.SettingsCardDivider()
                        }
                        ComposableSettings.SettingsCardRow {
                            FileTypeRow(
                                fileExtension: entry.fileExtension,
                                languageName: entry.languageName,
                                iconName: entry.iconName,
                                isCustom: false
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Filtered Data

    private var filteredCustomMappings: [CustomFileTypeMapping] {
        if searchText.isEmpty { return customMappings }
        let query = searchText.lowercased()
        return customMappings.filter {
            $0.fileExtension.lowercased().contains(query)
            || $0.languageName.lowercased().contains(query)
        }
    }

    private var filteredBuiltInTypes: [BuiltInFileType] {
        if searchText.isEmpty { return builtInTypes }
        let query = searchText.lowercased()
        return builtInTypes.filter {
            $0.fileExtension.lowercased().contains(query)
            || $0.languageName.lowercased().contains(query)
        }
    }

    // MARK: - Actions

    private func addCustomMapping(_ mapping: CustomFileTypeMapping) {
        customMappings.append(mapping)
        customMappings.sort {
            $0.fileExtension.localizedCaseInsensitiveCompare($1.fileExtension) == .orderedAscending
        }
        CustomFileTypeMappings.save(customMappings)
    }

    private func removeCustomMapping(_ mapping: CustomFileTypeMapping) {
        customMappings.removeAll { $0.fileExtension == mapping.fileExtension }
        CustomFileTypeMappings.save(customMappings)
    }
}

// MARK: - File Type Row

/// A single row displaying a file type's extension, language name, and icon.
///
/// The row draws no padding of its own: `SettingsCardRow` supplies the card's
/// insets, so every row in the window lines up whether it was built here or in
/// an AppKit panel.
private struct FileTypeRow: View {
    public let fileExtension: String
    public let languageName: String
    public let iconName: String
    public let isCustom: Bool
    /// Supplied for a custom mapping, which the user can take back out; `nil`
    /// for a built-in one, which is not theirs to remove.
    public var onRemove: (() -> Void)?

    @Environment(\.theme) private var theme

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .frame(width: 20)
                .foregroundStyle(isCustom ? theme.accent : theme.secondaryText)

            Text(".\(fileExtension)")
                .font(theme.font(.code))
                .frame(width: 100, alignment: .leading)

            Text(languageName)
                .foregroundStyle(theme.secondaryText)

            Spacer()

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.borderless)
                .help("Remove the custom mapping for .\(fileExtension)")
            }
        }
    }
}

// MARK: - Add Custom File Type Sheet

/// Sheet for adding a new custom file type mapping.
private struct AddCustomFileTypeSheet: View {
    public let existingExtensions: Set<String>
    public let onSave: (CustomFileTypeMapping) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var fileExtension = ""
    @State private var languageName = ""
    @State private var selectedIcon = "doc"

    /// Common SF Symbol icon choices for file types.
    private let iconChoices: [(name: String, symbol: String)] = [
        ("Document", "doc"),
        ("Text Document", "doc.text"),
        ("Rich Text", "doc.richtext"),
        ("Code", "chevron.left.forwardslash.chevron.right"),
        ("Terminal", "terminal"),
        ("Globe", "globe"),
        ("Curly Braces", "curlybraces"),
        ("Gear", "gearshape.2"),
        ("Photo", "photo"),
        ("Hammer", "hammer.fill"),
        ("Lock", "lock.shield"),
        ("Eye Slash", "eye.slash"),
        ("Circle", "circle.fill")
    ]

    private var isValid: Bool {
        let ext = fileExtension.trimmingCharacters(in: .whitespaces).lowercased()
        return !ext.isEmpty
            && !languageName.trimmingCharacters(in: .whitespaces).isEmpty
            && !existingExtensions.contains(ext)
    }

    private var extensionConflict: Bool {
        let ext = fileExtension.trimmingCharacters(in: .whitespaces).lowercased()
        return !ext.isEmpty && existingExtensions.contains(ext)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text("Add Custom File Type")
                .font(theme.font(.heading))
                .padding(.top, 16)
                .padding(.bottom, 12)

            Form {
                Section {
                    TextField("Extension (without dot)", text: $fileExtension)
                        .textFieldStyle(.roundedBorder)

                    if extensionConflict {
                        Text("A custom mapping for this extension already exists.")
                            .font(theme.font(.caption))
                            .foregroundStyle(theme.danger)
                    }
                }

                Section {
                    TextField("Language Name", text: $languageName)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                        ForEach(iconChoices, id: \.symbol) { choice in
                            Button {
                                selectedIcon = choice.symbol
                            } label: {
                                Image(systemName: choice.symbol)
                                    .font(.title3)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        selectedIcon == choice.symbol
                                            ? theme.accent.opacity(0.2)
                                            : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help(choice.name)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    let mapping = CustomFileTypeMapping(
                        fileExtension: fileExtension
                            .trimmingCharacters(in: .whitespaces)
                            .lowercased()
                            .replacingOccurrences(of: ".", with: ""),
                        languageName: languageName.trimmingCharacters(in: .whitespaces),
                        iconName: selectedIcon
                    )
                    onSave(mapping)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 400, height: 420)
    }
}
