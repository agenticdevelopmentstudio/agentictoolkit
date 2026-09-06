//
//  LanguageServerConfiguration.swift
//  AgenticToolkit
//

import Foundation

/// User-editable description of one language server.
///
/// The non-secret parts (id, name, the languages it serves, how to launch it,
/// how to find its workspace root) live here. Secret environment values are
/// stored separately under `UserSettings.languageServerSecrets`, keyed by
/// `id.uuidString`, so they route to the secure provider (Keychain) without
/// leaking into the regular settings file. This is the same split
/// `MCPServerConfiguration` makes, for the same reason.
public struct LanguageServerConfiguration: Codable, Sendable, Identifiable, Equatable, Hashable {

    public let id: UUID

    /// Shown in settings and used in log messages.
    public var name: String

    /// Every LSP language id this server serves — `"swift"`, `"typescript"`,
    /// `"python"`. Plain `String`s on purpose: the `CodeLanguage` -> language-id
    /// mapping (`LanguageDetection.lspLanguageId(for:)`) lives in
    /// `AgenticToolkitMacOS`, which sits *above* this target, and dependencies
    /// point downward only. The caller supplies the string.
    public var languageIds: [String]

    /// Absolute path to the server executable, e.g. `/usr/bin/sourcekit-lsp`.
    /// A path rather than a bare name: the app is sandboxed and launched from
    /// Finder, so its `PATH` is not the user's shell `PATH` and a bare name
    /// would resolve differently in a terminal build than in the shipped app.
    public var command: String

    public var arguments: [String]

    /// Non-secret environment overrides, merged over the parent environment.
    /// Secrets for this server are merged in on top by the registry.
    public var environment: [String: String]

    /// File and directory names that mark a workspace root, most specific
    /// first — `["Package.swift", ".git"]` for Swift. `LanguageServerRegistry`
    /// walks up from a starting directory looking for the first of these.
    public var rootMarkers: [String]

    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        languageIds: [String],
        command: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        rootMarkers: [String] = [".git"],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.languageIds = languageIds
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.rootMarkers = rootMarkers
        self.isEnabled = isEnabled
    }
}

/// Per-server secret environment values, keyed by
/// `LanguageServerConfiguration.id.uuidString`.
///
/// Outer key is the server's UUID (as a string so the value is plain
/// `Codable`), inner dictionary maps environment-variable name to its secret
/// value. Mirrors `MCPServerSecrets`.
public typealias LanguageServerSecrets = [String: [String: String]]
