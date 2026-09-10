//
//  NotImplementedLedger.swift
//  AgenticToolkit
//

import Foundation

/// One VS Code API member an extension reached for that this host does not
/// implement yet, and how hard it reached.
///
/// A value type, and deliberately not a view onto `ExtensionHost`: the report
/// that shows a user why their extension did nothing (task 5.8) has to be able
/// to render this list long after the host that produced it was torn down, and
/// must never be able to reach back into a live JavaScript context to do it.
public struct NotImplementedAccess: Sendable, Equatable {

    /// Whose extension asked. Kept on the access rather than only as a
    /// dictionary key, so a caller holding one row can always attribute it —
    /// the report groups by extension, but a log line or a single-row
    /// diagnostic does not.
    public let extensionIdentifier: String

    /// The member as an extension author would type it —
    /// `vscode.commands.registerCommand`, or a bare `fetch` for a global.
    /// Exactly the string the thrown JavaScript error names, so a user can
    /// match the two by eye.
    public let memberPath: String

    /// When this member was first reached for. First, not last: the interesting
    /// question is whether the extension tripped on it during activation or
    /// only later, and a last-access stamp answers neither.
    public let firstAccess: Date

    /// How many times the extension *used* it and was refused, including the
    /// first. An extension that polls a missing member in a timer produces a
    /// very different report from one that touched it once at startup, and
    /// collapsing both to "seen" would hide that.
    public let count: Int

    /// How many times the extension merely *asked whether it existed* and was
    /// told no — `'x' in vscode.commands`, `Object.keys(...)`,
    /// `getOwnPropertyDescriptor(...)`.
    ///
    /// Separate from `count`, because the two say different things about the
    /// same extension. A refused use is an extension that broke; a negative
    /// probe is an extension that looked, found nothing, and quietly took its
    /// fallback path — which is often the *more* interesting row in a report,
    /// since nothing else in the system would ever notice it happened. A member
    /// can carry both: a library commonly feature-detects once and then calls
    /// anyway.
    public let probeCount: Int

    public init(
        extensionIdentifier: String,
        memberPath: String,
        firstAccess: Date,
        count: Int,
        probeCount: Int = 0
    ) {
        self.extensionIdentifier = extensionIdentifier
        self.memberPath = memberPath
        self.firstAccess = firstAccess
        self.count = count
        self.probeCount = probeCount
    }
}

/// The record of everything extensions asked this host for and did not get.
///
/// Deduplicated by (extension, member path) rather than appended to: a member
/// reached for inside a render loop would otherwise produce thousands of
/// identical rows and drown the handful that matter. `count` is what survives
/// the deduplication.
///
/// A reference type held by whoever outlives the hosts — one ledger shared by
/// every `ExtensionHost` gives the report a single place to read, and a host
/// that makes its own is the honest default for a caller that has only one.
/// Nothing in here touches JavaScript, so the ledger stays readable after every
/// host that wrote to it has been disposed.
@MainActor
public final class NotImplementedLedger {

    private struct Key: Hashable {
        let extensionIdentifier: String
        let memberPath: String
    }

    private var entries: [Key: NotImplementedAccess] = [:]

    public init() {}

    /// Every access, ordered by extension and then by member path.
    ///
    /// Sorted rather than in first-seen order: this is what a report renders,
    /// and a list whose order depends on which member an extension happened to
    /// touch first reads as noise and cannot be diffed between two runs.
    public var accesses: [NotImplementedAccess] {
        entries.values.sorted {
            if $0.extensionIdentifier != $1.extensionIdentifier {
                return $0.extensionIdentifier < $1.extensionIdentifier
            }
            return $0.memberPath < $1.memberPath
        }
    }

    /// Everything one extension asked for, in the same order.
    public func accesses(for extensionIdentifier: String) -> [NotImplementedAccess] {
        accesses.filter { $0.extensionIdentifier == extensionIdentifier }
    }

    /// Records one reach for `memberPath`, or bumps the count of one already
    /// recorded. `firstAccess` is set once and never moved.
    @discardableResult
    public func record(memberPath: String, extensionIdentifier: String) -> NotImplementedAccess {
        bump(memberPath: memberPath, extensionIdentifier: extensionIdentifier, wasProbe: false)
    }

    /// Records one *negative probe* — a feature-detection question that was
    /// honestly answered "no".
    ///
    /// Shares a row with `record`, deliberately: `'x' in ns` followed by `ns.x`
    /// is one library guarding one call, and two rows would read as two
    /// different members.
    @discardableResult
    public func recordProbe(memberPath: String, extensionIdentifier: String) -> NotImplementedAccess {
        bump(memberPath: memberPath, extensionIdentifier: extensionIdentifier, wasProbe: true)
    }

    private func bump(
        memberPath: String,
        extensionIdentifier: String,
        wasProbe: Bool
    ) -> NotImplementedAccess {
        let key = Key(extensionIdentifier: extensionIdentifier, memberPath: memberPath)
        let existing = entries[key]
        let updated = NotImplementedAccess(
            extensionIdentifier: extensionIdentifier,
            memberPath: memberPath,
            firstAccess: existing?.firstAccess ?? Date(),
            count: (existing?.count ?? 0) + (wasProbe ? 0 : 1),
            probeCount: (existing?.probeCount ?? 0) + (wasProbe ? 1 : 0)
        )
        entries[key] = updated
        return updated
    }
}
