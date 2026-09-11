//
//  ActivationEventMatcher.swift
//  AgenticToolkit
//

import Foundation

/// One parsed `activationEvents` entry.
///
/// VS Code extensions declare activation events as free-form strings — this
/// is what turns `"onLanguage:swift"` into something a host can actually
/// compare against a trigger, rather than re-parsing the same five prefixes
/// at every call site.
public struct ActivationEvent: Sendable, Equatable {

    public enum Kind: Sendable, Equatable {
        case any                        // "*"
        case startupFinished            // "onStartupFinished"
        case language(String)           // "onLanguage:swift"      -> "swift"
        case command(String)            // "onCommand:foo.bar"     -> "foo.bar"
        case workspaceContains(String)  // "workspaceContains:**/*.csproj" -> the glob
    }

    public let kind: Kind

    /// The entry exactly as the manifest spelled it, so a diagnostic can quote
    /// what the author wrote rather than what we understood.
    public let rawValue: String

    /// Parses one `activationEvents` entry.
    ///
    /// Leading and trailing whitespace is trimmed before recognising the
    /// shape — a manifest with `"  onStartupFinished  "` is not unusual, and
    /// there is nothing for the trailing space to mean once it is not part of
    /// a payload. What follows a colon is taken verbatim and is
    /// case-sensitive: VS Code language and command ids are lowercase by
    /// convention but the editor never normalises them, so normalising here
    /// would accept manifests VS Code itself would not activate.
    ///
    /// An entry with an empty payload after the colon (`"onLanguage:"`) is
    /// unrecognized rather than read as matching the empty string — an author
    /// who wrote that made a mistake, and there is no trigger this host could
    /// ever produce that such an entry should fire on.
    public init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed == "*" {
            kind = .any
        } else if trimmed == "onStartupFinished" {
            kind = .startupFinished
        } else if let payload = Self.payload(afterPrefix: "onLanguage:", in: trimmed) {
            kind = .language(payload)
        } else if let payload = Self.payload(afterPrefix: "onCommand:", in: trimmed) {
            kind = .command(payload)
        } else if let payload = Self.payload(afterPrefix: "workspaceContains:", in: trimmed) {
            kind = .workspaceContains(payload)
        } else {
            return nil
        }

        self.rawValue = rawValue
    }

    /// `nil` when `value` does not start with `prefix`, or when everything
    /// after it is empty — the shared rule that makes `"onLanguage:"` and
    /// friends unrecognized rather than a match on `""`.
    private static func payload(afterPrefix prefix: String, in value: String) -> String? {
        guard value.hasPrefix(prefix) else { return nil }
        let payload = String(value.dropFirst(prefix.count))
        return payload.isEmpty ? nil : payload
    }
}

/// A thing that just happened, which may or may not wake an extension.
public enum ActivationTrigger: Sendable, Equatable {
    case startupFinished
    case documentOpened(languageID: String)
    case commandInvoked(String)

    /// The workspace's contents, as paths relative to the workspace root, with
    /// `/` separators and no leading slash. The caller does the directory walk;
    /// this type does pure pattern matching and touches no filesystem.
    case workspaceScanned(relativePaths: [String])
}

/// Decides whether a manifest's `activationEvents` (and, from VS Code 1.74,
/// its declared commands) wake it for a given trigger.
///
/// Built once from a manifest and then queried repeatedly — `events` is
/// captured at `init` rather than re-parsed on every `matches(_:)` call, since
/// a host may check the same extension against many triggers over its
/// lifetime (each document opened, each command invoked).
public struct ActivationEventMatcher: Sendable, Equatable {

    /// Every entry we understood, in manifest order.
    public let events: [ActivationEvent]

    /// Entries we did not understand, raw, in manifest order. Never dropped
    /// silently — a later task reports them.
    public let unrecognizedEvents: [String]

    /// `workspaceContains:` globs whose syntax this matcher does not support.
    /// They never match; they are surfaced here so a report can say so rather
    /// than leaving an author wondering why their extension never woke.
    public let unsupportedPatterns: [String]

    /// Command ids that wake this extension *without* an `onCommand:` entry,
    /// because it declares an engine of 1.74.0 or later. Empty otherwise.
    public let implicitlyActivatingCommands: Set<String>

    /// True when the manifest declares `"*"`. Such an extension activates as
    /// soon as the host is ready, without waiting for a specific trigger.
    public var activatesEagerly: Bool {
        events.contains { $0.kind == .any }
    }

    /// The VS Code version, as a `SemanticVersion`, from which a declared
    /// command activates its extension without an explicit `onCommand:`
    /// entry — see the "Implicit activation from contributions.commands"
    /// note on `matches(_:)`.
    private static let implicitCommandActivationFloor = SemanticVersion(major: 1, minor: 74, patch: 0)

    /// Builds a matcher from a manifest's `activationEvents` and declared
    /// commands.
    ///
    /// Parses every `activationEvents` entry once, up front, sorting them
    /// into `events` (recognised) and `unrecognizedEvents` (not); does the
    /// same triage for `workspaceContains:` globs into `unsupportedPatterns`,
    /// so a caller never has to re-derive "did this glob parse" for itself.
    /// It also computes `implicitlyActivatingCommands`: from VS Code 1.74, a
    /// command already declared in `contributes.commands` activates its
    /// extension without a matching `onCommand:` entry.
    ///
    /// The version test is the extension's own declared engine, not the
    /// host's: an extension that still targets an older VS Code cannot rely
    /// on behaviour its stated minimum predates. A manifest whose
    /// `engines.vscode` does not parse gets no implicit activation — an
    /// engine string this host cannot evaluate is not evidence the extension
    /// supports the newer inference.
    public init(manifest: ExtensionManifest) {
        var parsed: [ActivationEvent] = []
        var unrecognized: [String] = []
        for raw in manifest.activationEvents {
            if let event = ActivationEvent(rawValue: raw) {
                parsed.append(event)
            } else {
                unrecognized.append(raw)
            }
        }
        events = parsed
        unrecognizedEvents = unrecognized

        var unsupported: [String] = []
        for event in parsed {
            if case .workspaceContains(let glob) = event.kind, GlobPattern(glob) == nil {
                unsupported.append(glob)
            }
        }
        unsupportedPatterns = unsupported

        if let range = VSCodeEngineRange(manifest.engines.vscode),
           range.minimumVersion >= Self.implicitCommandActivationFloor {
            let commandIDs = manifest.contributes?.commands.map(\.command) ?? []
            implicitlyActivatingCommands = Set(commandIDs)
        } else {
            implicitlyActivatingCommands = []
        }
    }

    /// Whether `trigger` wakes this extension.
    ///
    /// An extension with no recognised events and no implicitly activating
    /// commands never matches anything here — it does not fall back to
    /// eager activation. `"*"` is the only entry that means "activate
    /// unconditionally," and it is handled explicitly rather than by
    /// treating an empty `events` as a wildcard.
    public func matches(_ trigger: ActivationTrigger) -> Bool {
        if activatesEagerly { return true }

        switch trigger {
        case .startupFinished:
            return events.contains { $0.kind == .startupFinished }

        case .documentOpened(let languageID):
            return events.contains {
                if case .language(let declared) = $0.kind { return declared == languageID }
                return false
            }

        case .commandInvoked(let commandID):
            if implicitlyActivatingCommands.contains(commandID) { return true }
            return events.contains {
                if case .command(let declared) = $0.kind { return declared == commandID }
                return false
            }

        case .workspaceScanned(let relativePaths):
            return events.contains { event in
                guard case .workspaceContains(let glob) = event.kind else { return false }
                // A glob already recorded in `unsupportedPatterns` fails to
                // construct here too and simply never matches — the two
                // never disagree because both ask the same question.
                guard let pattern = GlobPattern(glob) else { return false }
                return relativePaths.contains { pattern.matches($0) }
            }
        }
    }
}

/// A minimal glob matcher for `workspaceContains:` patterns.
///
/// Deliberately file-local for now rather than its own file: `abstractr
/// exports` has no glob, fnmatch or wildcard matcher anywhere in this
/// toolkit, and creating a second new file in this shared tier for a type
/// with exactly one caller would trip the placement gate for no benefit.
/// Promote it to its own file the moment a second consumer arrives — task
/// 5.4's `workspace.findFiles` is the likely one — rather than growing a
/// second copy elsewhere.
///
/// Implemented as a straightforward backtracking matcher over the pattern's
/// tokens and the path's characters, not `NSRegularExpression`: translating
/// glob to regex requires escaping every regex metacharacter that is also a
/// legal filename character, and a missed one turns a literal `.` or `+` in
/// a real filename into a wildcard.
internal struct GlobPattern {

    private enum Token {
        case literal(Character)
        /// `*` — any run of characters except `/`, including empty.
        case star
        /// `**` on its own — any run of characters *including* `/`,
        /// including empty. Distinct from `anyDirectories` below: a bare
        /// `**` not immediately followed by `/` carries no directory-segment
        /// meaning, just "anything, including slashes."
        case doubleStar
        /// `?` — exactly one character, not `/`.
        case question
        /// `**/` as one unit, tokenized together rather than as `doubleStar`
        /// followed by a literal `/`. That distinction is the whole reason
        /// this case exists: a leading `**/` must also match *zero*
        /// directories, i.e. the slash itself is allowed to vanish along
        /// with everything `**` would have consumed. A plain literal `/`
        /// token after `doubleStar` could never do that — it would still
        /// demand an actual `/` character in the path even when `**` matched
        /// nothing. This token instead matches zero or more path segments,
        /// each ending in `/`.
        case anyDirectories
        /// `{a,b,c}` — each alternative's own token list is tokenized once,
        /// up front, and stored in `branches` under a stable id; this case
        /// holds only the ids for its own alternatives, not the token lists
        /// themselves. Nested `{` is rejected at parse time.
        case alternation([BranchID])
    }

    /// Identifies one `{...}` branch's own token list within `branches`.
    /// Assigned once at tokenize time and never reused for another branch —
    /// see `matchBranch` for why that makes it a sufficient memoization key
    /// on its own, without also carrying which `.alternation` token or which
    /// outer array it belongs to.
    private typealias BranchID = Int

    private let tokens: [Token]

    /// Every `{...}` branch's own token list, flattened out of the pattern's
    /// tree and indexed by `BranchID`. `tokenize` rejects a nested `{`, so a
    /// branch can only ever hold `literal`/`star`/`doubleStar`/`question`/
    /// `anyDirectories` tokens — never another `.alternation` — which is
    /// exactly what lets `matchBranch` treat every branch as belonging to
    /// exactly one `.alternation` token, at exactly one fixed index in
    /// `tokens`.
    private let branches: [[Token]]

    /// `nil` when `pattern` uses syntax this matcher does not support: a
    /// `[...]` character class, a leading `!` negation, or a nested `{`
    /// inside a `{...}` group. Those are refused rather than approximated —
    /// silently treating `[` as a literal would make a pattern match paths
    /// its author never intended it to.
    init?(_ pattern: String) {
        guard !pattern.contains("["), !pattern.hasPrefix("!") else { return nil }
        var branches: [[Token]] = []
        guard let tokens = Self.tokenize(Array(pattern), &branches) else { return nil }
        self.tokens = tokens
        self.branches = branches
    }

    /// Tokenizes `characters`, appending each `{...}` branch it discovers
    /// (its own already-tokenized contents) to the shared `branches` table
    /// and recording only that branch's index in the `.alternation` token —
    /// so every branch, anywhere in the pattern, ends up with a single
    /// stable id it keeps for the lifetime of this `GlobPattern`.
    private static func tokenize(_ characters: [Character], _ branches: inout [[Token]]) -> [Token]? {
        var tokens: [Token] = []
        var index = 0
        while index < characters.count {
            switch characters[index] {
            case "*":
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    if index + 2 < characters.count, characters[index + 2] == "/" {
                        tokens.append(.anyDirectories)
                        index += 3
                    } else {
                        tokens.append(.doubleStar)
                        index += 2
                    }
                } else {
                    tokens.append(.star)
                    index += 1
                }

            case "?":
                tokens.append(.question)
                index += 1

            case "{":
                guard let closeIndex = characters[(index + 1)...].firstIndex(of: "}") else { return nil }
                let inner = characters[(index + 1)..<closeIndex]
                guard !inner.contains("{") else { return nil }

                let alternatives = inner.split(separator: ",", omittingEmptySubsequences: false)
                var branchIDs: [BranchID] = []
                for alternative in alternatives {
                    guard let branchTokens = tokenize(Array(alternative), &branches) else { return nil }
                    branchIDs.append(branches.count)
                    branches.append(branchTokens)
                }
                tokens.append(.alternation(branchIDs))
                index = closeIndex + 1

            case let character:
                tokens.append(.literal(character))
                index += 1
            }
        }
        return tokens
    }

    /// A `(tokenIndex, pathIndex)` pair identifies one state in `tokens`'s
    /// backtracking search — see `matchTokens` below for why that pair alone
    /// is enough to memoize on.
    private struct MemoKey: Hashable {
        let tokenIndex: Int
        let pathIndex: Int
    }

    /// A `(branch, branchIndex, pathIndex)` triple identifies one state in a
    /// `{...}` branch's own backtracking search — see `matchBranch`.
    private struct BranchMemoKey: Hashable {
        let branch: BranchID
        let branchIndex: Int
        let pathIndex: Int
    }

    /// Whether `path` matches this pattern, anchored at both ends — the
    /// whole relative path, not a substring of it.
    func matches(_ path: String) -> Bool {
        var memo: [MemoKey: Bool] = [:]
        var branchMemo: [BranchMemoKey: Bool] = [:]
        return Self.matchTokens(tokens, 0, Array(path), 0, branches, &memo, &branchMemo)
    }

    /// Whether `path[pathIndex...]` matches `tokens[tokenIndex...]`.
    ///
    /// Memoized on `(tokenIndex, pathIndex)`: for a fixed `tokens` array and
    /// `path`, that pair alone determines the answer — two calls with the
    /// same indices explore exactly the same remaining search space and must
    /// return the same result. Without the cache, a pattern like
    /// `a**a**a**a**a**a**a**b` matched against a long run of `a` characters
    /// re-derives the same failing `(tokenIndex, pathIndex)` state through
    /// every combination of how much each `**` consumed — the search time
    /// roughly doubles per added `**` segment. Caching collapses that to one
    /// evaluation per state: `O(tokens.count * path.count)` states, each
    /// doing at most `O(path.count)` work, rather than exponential
    /// re-exploration. Every recursive call below either advances
    /// `tokenIndex` or (for `.anyDirectories`, which can repeat the same
    /// token) strictly advances `pathIndex`, so the state space has no
    /// cycles and it is safe to cache each result only once its full value
    /// is known.
    ///
    /// `.alternation` is the one case that does not recurse into this same
    /// `tokens` array — see `matchBranch`. The same blowup this cache guards
    /// against is just as reachable through a single, comma-less `{...}`
    /// group wrapping a wildcard-heavy pattern (e.g.
    /// `{a**a**a**a**a**a**a**b}` parses to one `.alternation` with one
    /// branch holding that same adversarial token list), so `matchBranch`
    /// keeps an equivalent cache of its own rather than leaning on this one.
    private static func matchTokens(
        _ tokens: [Token], _ tokenIndex: Int, _ path: [Character], _ pathIndex: Int,
        _ branches: [[Token]], _ memo: inout [MemoKey: Bool], _ branchMemo: inout [BranchMemoKey: Bool]
    ) -> Bool {
        guard tokenIndex < tokens.count else { return pathIndex == path.count }

        let key = MemoKey(tokenIndex: tokenIndex, pathIndex: pathIndex)
        if let cached = memo[key] { return cached }

        let result: Bool
        switch tokens[tokenIndex] {
        case .literal(let expected):
            if pathIndex < path.count, path[pathIndex] == expected {
                result = matchTokens(tokens, tokenIndex + 1, path, pathIndex + 1, branches, &memo, &branchMemo)
            } else {
                result = false
            }

        case .question:
            if pathIndex < path.count, path[pathIndex] != "/" {
                result = matchTokens(tokens, tokenIndex + 1, path, pathIndex + 1, branches, &memo, &branchMemo)
            } else {
                result = false
            }

        case .star:
            var matched = matchTokens(tokens, tokenIndex + 1, path, pathIndex, branches, &memo, &branchMemo)
            var cursor = pathIndex
            while !matched, cursor < path.count, path[cursor] != "/" {
                cursor += 1
                matched = matchTokens(tokens, tokenIndex + 1, path, cursor, branches, &memo, &branchMemo)
            }
            result = matched

        case .doubleStar:
            var matched = matchTokens(tokens, tokenIndex + 1, path, pathIndex, branches, &memo, &branchMemo)
            var cursor = pathIndex
            while !matched, cursor < path.count {
                cursor += 1
                matched = matchTokens(tokens, tokenIndex + 1, path, cursor, branches, &memo, &branchMemo)
            }
            result = matched

        case .anyDirectories:
            // Zero directories first — the case a plain `doubleStar` +
            // literal `/` could never express.
            var matched = matchTokens(tokens, tokenIndex + 1, path, pathIndex, branches, &memo, &branchMemo)
            var cursor = pathIndex
            while !matched, cursor < path.count {
                if path[cursor] == "/" {
                    // Consumed one segment ending at this slash; recurse on
                    // the *same* token so further segments can follow.
                    matched = matchTokens(tokens, tokenIndex, path, cursor + 1, branches, &memo, &branchMemo)
                }
                cursor += 1
            }
            result = matched

        case .alternation(let branchIDs):
            result = branchIDs.contains { branchID in
                matchBranch(
                    branchID, branches[branchID], 0, tokens, tokenIndex + 1, path, pathIndex,
                    branches, &memo, &branchMemo
                )
            }
        }

        memo[key] = result
        return result
    }

    /// Matches branch `branchID` (its token list, `branch`, is always
    /// `branches[branchID]` — passed in directly so callers don't re-look it
    /// up), starting at `branchIndex`, against `path` starting at
    /// `pathIndex`; `outerTokenIndex` in `outerTokens` is where to resume
    /// once the branch is exhausted.
    ///
    /// Memoized on `(branchID, branchIndex, pathIndex)` — a smaller version
    /// of the same problem `matchTokens` solves, and needed for the same
    /// reason: `.star`/`.doubleStar`/`.anyDirectories` inside a branch can
    /// backtrack exponentially too. `{a**a**a**a**a**a**a**b}` is exactly
    /// `matchTokens`'s adversarial pattern wrapped in one comma-less group —
    /// before this cache existed, `matchBranch` reached that same blowup
    /// with no bound at all, since its only contact with any cache was the
    /// one terminal delegation below.
    ///
    /// `branchID` alone is enough to identify which branch a state belongs
    /// to — the key does not also need `outerTokens`/`outerTokenIndex` —
    /// because `tokenize` rejects a nested `{`, so every branch belongs to
    /// exactly one `.alternation` token, which sits at exactly one index in
    /// exactly one array (always `self.tokens`, since `.alternation` can
    /// only ever appear there, never inside a branch). `outerTokenIndex` is
    /// therefore a constant function of `branchID`, not a separate degree of
    /// freedom the key would need to distinguish. For the same reason,
    /// `branch` can never itself contain `.alternation`, so there is no case
    /// for it below.
    ///
    /// Relax either of those two facts — the nested-`{` rejection, or one
    /// branch belonging to one `.alternation` — and this key stops being
    /// sufficient. It would then go on returning answers, just wrong ones,
    /// so change the key in the same edit.
    private static func matchBranch(
        _ branchID: BranchID, _ branch: [Token], _ branchIndex: Int,
        _ outerTokens: [Token], _ outerTokenIndex: Int,
        _ path: [Character], _ pathIndex: Int,
        _ branches: [[Token]], _ memo: inout [MemoKey: Bool], _ branchMemo: inout [BranchMemoKey: Bool]
    ) -> Bool {
        guard branchIndex < branch.count else {
            return matchTokens(outerTokens, outerTokenIndex, path, pathIndex, branches, &memo, &branchMemo)
        }

        let key = BranchMemoKey(branch: branchID, branchIndex: branchIndex, pathIndex: pathIndex)
        if let cached = branchMemo[key] { return cached }

        let result: Bool
        switch branch[branchIndex] {
        case .literal(let expected):
            if pathIndex < path.count, path[pathIndex] == expected {
                result = matchBranch(
                    branchID, branch, branchIndex + 1, outerTokens, outerTokenIndex, path, pathIndex + 1,
                    branches, &memo, &branchMemo
                )
            } else {
                result = false
            }

        case .question:
            if pathIndex < path.count, path[pathIndex] != "/" {
                result = matchBranch(
                    branchID, branch, branchIndex + 1, outerTokens, outerTokenIndex, path, pathIndex + 1,
                    branches, &memo, &branchMemo
                )
            } else {
                result = false
            }

        case .star:
            var matched = matchBranch(
                branchID, branch, branchIndex + 1, outerTokens, outerTokenIndex, path, pathIndex,
                branches, &memo, &branchMemo
            )
            var cursor = pathIndex
            while !matched, cursor < path.count, path[cursor] != "/" {
                cursor += 1
                matched = matchBranch(
                    branchID, branch, branchIndex + 1, outerTokens, outerTokenIndex, path, cursor,
                    branches, &memo, &branchMemo
                )
            }
            result = matched

        case .doubleStar:
            var matched = matchBranch(
                branchID, branch, branchIndex + 1, outerTokens, outerTokenIndex, path, pathIndex,
                branches, &memo, &branchMemo
            )
            var cursor = pathIndex
            while !matched, cursor < path.count {
                cursor += 1
                matched = matchBranch(
                    branchID, branch, branchIndex + 1, outerTokens, outerTokenIndex, path, cursor,
                    branches, &memo, &branchMemo
                )
            }
            result = matched

        case .anyDirectories:
            var matched = matchBranch(
                branchID, branch, branchIndex + 1, outerTokens, outerTokenIndex, path, pathIndex,
                branches, &memo, &branchMemo
            )
            var cursor = pathIndex
            while !matched, cursor < path.count {
                if path[cursor] == "/" {
                    matched = matchBranch(
                        branchID, branch, branchIndex, outerTokens, outerTokenIndex, path, cursor + 1,
                        branches, &memo, &branchMemo
                    )
                }
                cursor += 1
            }
            result = matched

        case .alternation:
            // Unreachable: `branch` came from `tokenize`, which rejects a
            // nested `{` inside a `{...}` group before this ever runs.
            preconditionFailure("a { ... } branch cannot itself contain a nested alternation")
        }

        branchMemo[key] = result
        return result
    }
}
