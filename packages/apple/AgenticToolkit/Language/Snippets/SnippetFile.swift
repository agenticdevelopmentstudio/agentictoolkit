//
//  SnippetFile.swift
//  AgenticToolkit
//

import AgenticToolkitCore
import Foundation

/// Why a snippet file produced no snippets.
///
/// Thrown rather than swallowed, and never turned into an empty array: a file
/// the user installed and a file the reader could not understand must not look
/// the same to the caller. Real extensions ship both a snippets file that is
/// malformed once its commented-out majority is stripped, and a snippets file
/// that is nothing but a comment because the extension writes its real
/// snippets from code at runtime — silently importing zero snippets from
/// either is a bug report nobody can act on.
public enum SnippetFileParseError: Error, Equatable {
    /// The document parsed, but its root was not a JSON object. The format is
    /// an object whose keys are snippet names; there is no other shape.
    case notAnObject
}

/// Reads one VS Code snippets file — the `path` of a `contributes.snippets`
/// entry — into `ExtensionSnippet`s.
///
/// A caseless namespace, like `VSCodeThemeImporter`: the file is read by key
/// off a deserialized document rather than decoded into a `Codable` struct,
/// because real files carry keys the schema never documented (`key`,
/// `isFileTemplate`, a category name from a file that nests one level too
/// deep, and at least one misspelling of `description`) and a strict decoder
/// would reject the whole file over any of them. Unknown keys are ignored;
/// they are never grounds for rejecting a snippet.
public enum SnippetFile {

    // MARK: - Public API

    /// Every snippet in `data`.
    ///
    /// - Throws: `SnippetFileParseError.notAnObject`, or whatever
    ///   `JSONCPreprocessor` throws for a document that will not parse.
    public static func parse(_ data: Data, extensionIdentifier: String) throws -> [ExtensionSnippet] {
        guard let root = try JSONCPreprocessor.jsonObject(from: data) as? [String: Any] else {
            throw SnippetFileParseError.notAnObject
        }
        // Sorted by name because a deserialized JSON object has no order left
        // to preserve, and an unordered result would reshuffle the completion
        // list between launches for no reason the user could see.
        return root.keys.sorted().compactMap { name in
            guard let object = root[name] as? [String: Any] else { return nil }
            return snippet(named: name, from: object, extensionIdentifier: extensionIdentifier)
        }
    }

    /// Every snippet in the file at `url`.
    ///
    /// - Throws: the read error when the file cannot be read, and everything
    ///   `parse(_:extensionIdentifier:)` throws.
    public static func parse(contentsOf url: URL, extensionIdentifier: String) throws -> [ExtensionSnippet] {
        try parse(Data(contentsOf: url), extensionIdentifier: extensionIdentifier)
    }

    // MARK: - One snippet

    /// One snippet object, or `nil` for an entry that could never be summoned.
    ///
    /// Two things make an entry unusable, and both are skipped rather than
    /// thrown for: a missing or non-textual `body` (there is nothing to
    /// insert) and a missing `prefix` (there is nothing to type). Skipping is
    /// right where throwing is not, because these are individual entries in a
    /// file whose *other* entries are fine — the file itself parsed.
    private static func snippet(
        named name: String,
        from object: [String: Any],
        extensionIdentifier: String
    ) -> ExtensionSnippet? {
        guard let prefix = object["prefix"] as? String, let body = body(from: object["body"]) else {
            return nil
        }
        return ExtensionSnippet(
            name: name,
            prefix: prefix,
            body: body,
            description: object["description"] as? String,
            scopes: scopes(from: object["scope"] as? String),
            extensionIdentifier: extensionIdentifier
        )
    }

    /// The snippet body as one string.
    ///
    /// Both shapes are common — an array of lines in three files out of five,
    /// a single string in the rest — so neither is the exception. The array's
    /// elements are lines, joined with the newline the file left out.
    private static func body(from value: Any?) -> String? {
        if let text = value as? String { return text }
        if let lines = value as? [String] { return lines.joined(separator: "\n") }
        return nil
    }

    /// A `scope` value as language ids.
    ///
    /// Comma-separated inside the file, unlike the manifest entry's single
    /// `language`. Empties are dropped so a stray `"swift,"` narrows to Swift
    /// rather than to Swift and a language with no name.
    private static func scopes(from value: String?) -> [String] {
        guard let value else { return [] }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
