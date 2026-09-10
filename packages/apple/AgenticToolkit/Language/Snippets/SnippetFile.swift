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

/// A sentence for the extensions panel, not a case name.
///
/// The conformance is here rather than a `switch` at the call site because
/// `SnippetStore` records `error.localizedDescription` for *every* error a read
/// can throw — Cocoa's file errors already describe themselves, and this is
/// what makes ours do the same. Without it Foundation invents "The operation
/// couldn't be completed. (…SnippetFileParseError error 0.)", which tells a
/// user nothing about what to fix in their snippets file.
extension SnippetFileParseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAnObject:
            return "The file's root is not a JSON object. A snippets file is an "
                 + "object whose keys are snippet names."
        }
    }
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
        return root.keys.sorted().flatMap { name -> [ExtensionSnippet] in
            guard let object = root[name] as? [String: Any] else { return [] }
            return snippets(named: name, from: object, extensionIdentifier: extensionIdentifier)
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

    /// One snippet object as snippets — one per declared prefix, or none for
    /// an entry that could never be summoned.
    ///
    /// **One entry can be several snippets.** VS Code's `prefix` takes an
    /// array as readily as a string, and packs that ship one snippet under
    /// several trigger words (`"prefix": ["rfc", "rface"]`) are common enough
    /// that a string-only cast dropped them wholesale — with no failure record,
    /// because a rejected entry and an absent one looked identical from here.
    /// `ExtensionSnippet` is one prefix by construction (`prefix` is what the
    /// completion item's label, filter text and lookup key all are), so an
    /// array becomes one snippet per element rather than a new plural field.
    ///
    /// Two things make an entry unusable, and both are skipped rather than
    /// thrown for: a missing or non-textual `body` (there is nothing to
    /// insert) and a missing, non-textual or empty `prefix` (there is nothing
    /// to type). Skipping is right where throwing is not, because these are
    /// individual entries in a file whose *other* entries are fine — the file
    /// itself parsed.
    private static func snippets(
        named name: String,
        from object: [String: Any],
        extensionIdentifier: String
    ) -> [ExtensionSnippet] {
        let prefixes = prefixes(from: object["prefix"])
        guard !prefixes.isEmpty, let body = body(from: object["body"]) else {
            return []
        }
        let description = object["description"] as? String
        let scopes = scopes(from: object["scope"] as? String)
        return prefixes.map { prefix in
            ExtensionSnippet(
                name: name,
                prefix: prefix,
                body: body,
                description: description,
                scopes: scopes,
                extensionIdentifier: extensionIdentifier
            )
        }
    }

    /// Every trigger word an entry declares, in declaration order.
    ///
    /// The same string-or-array tolerance `body(from:)` has carried all along,
    /// applied to the other half of the pair. Empties are dropped and the order
    /// is the file's: a prefix nobody can type is not a prefix, and a snippet
    /// list that reshuffles between launches is worse than one whose order is
    /// arbitrary but fixed.
    private static func prefixes(from value: Any?) -> [String] {
        let declared: [String]
        switch value {
        case let text as String:
            declared = [text]
        // Element-wise rather than `as? [String]`, so one stray `null` in an
        // otherwise good array costs that element and not the whole entry.
        case let list as [Any]:
            declared = list.compactMap { $0 as? String }
        default:
            return []
        }
        return declared.filter { !$0.isEmpty }
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
