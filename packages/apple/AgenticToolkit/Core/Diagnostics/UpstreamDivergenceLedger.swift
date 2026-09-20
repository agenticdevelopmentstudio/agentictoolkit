//
//  UpstreamDivergenceLedger.swift
//  AgenticToolkit
//

import Combine
import Foundation
import OSLog

/// One divergence, one distinguishing detail, and how often it has been seen.
///
/// The detail is part of the identity rather than a label on it — "two
/// documents each lost a token once" and "one document lost two tokens" are
/// different diagnoses, and a ledger that merged them would hide which language
/// server was misbehaving. What goes in it is the call site's choice; a
/// document URI or a server name is the useful thing, never anything drawn
/// from the file's contents.
public struct UpstreamDivergenceHit: Sendable, Hashable, Identifiable {

    public let divergence: UpstreamDivergence

    /// What distinguishes this occurrence from another of the same divergence.
    public let detail: String

    /// When this row was opened. Pinned, so a row can answer "did this start
    /// happening at some point" a week later.
    public let firstSeen: Date

    /// When it last happened. Moves, so the pair answers "is it still".
    public let lastSeen: Date

    /// How many times, totalled across every recording.
    public let count: Int

    public var id: String { "\(divergence.id)\u{1F}\(detail)" }

    public init(
        divergence: UpstreamDivergence,
        detail: String,
        firstSeen: Date,
        lastSeen: Date,
        count: Int
    ) {
        self.divergence = divergence
        self.detail = detail
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.count = count
    }
}

/// Where deliberate narrowings from VS Code's behaviour are recorded as they
/// actually happen.
///
/// The point is to make a decision that lives in a comment visible while real
/// extensions are being tried. Which of the catalogue's rows a given extension
/// trips over is not derivable by reading either side: it depends on what the
/// language servers that extension starts choose to send. So the ledger
/// answers the only question worth asking of a list of known narrowings —
/// *which ones does anything actually hit* — and does it from the running app
/// rather than from a re-reading of the source.
///
/// It is deliberately cheap: an in-memory dictionary behind a lock, no
/// persistence, cleared when the app quits. A narrowing worth acting on will
/// be hit again the next time the same extension is exercised, and a ledger
/// that survived launches would accumulate rows from code that has since been
/// changed — which is the failure mode of every stale diagnostic file.
///
/// `@unchecked Sendable` over a lock rather than an actor or `@MainActor`,
/// because the call sites span both: a language server session is an `actor`,
/// and the panel that displays this is main-actor UI. `record` has to be
/// callable synchronously from inside a decode loop without the loop becoming
/// async to reach it.
public final class UpstreamDivergenceLedger: @unchecked Sendable {

    /// The process-wide ledger. A `let` on a class with a public initialiser,
    /// so that a call site buried in a decode loop can record without being
    /// handed a dependency, while tests get a fresh instance each.
    public static let shared = UpstreamDivergenceLedger()

    private struct Key: Hashable {
        let divergenceID: String
        let detail: String
    }

    private let lock = NSLock()
    private var rows: [Key: UpstreamDivergenceHit] = [:]
    private let subject = CurrentValueSubject<[UpstreamDivergenceHit], Never>([])

    /// Held across a publication — reading the rows and sending them — so that
    /// two writers cannot send in the opposite order to the changes they are
    /// describing. `publish()` says what goes wrong without it.
    private let publishLock = NSLock()

    public init() {}

    /// Every row, ordered by divergence and then detail.
    ///
    /// Sorted rather than in arrival order because this is read by a person:
    /// the rows of one divergence belong together, and a list that reorders
    /// itself as new hits arrive cannot be read while it is changing.
    public var hits: [UpstreamDivergenceHit] {
        lock.lock()
        defer { lock.unlock() }
        return Self.sorted(rows)
    }

    /// Rows for one divergence only.
    public func hits(for divergence: UpstreamDivergence) -> [UpstreamDivergenceHit] {
        lock.lock()
        defer { lock.unlock() }
        return Self.sorted(rows.filter { $0.key.divergenceID == divergence.id })
    }

    /// The rows, now and on every change. A subscriber is handed the current
    /// value on subscribe, so a panel opened long after the damage was done
    /// still shows it.
    public var hitsPublisher: AnyPublisher<[UpstreamDivergenceHit], Never> {
        subject.eraseToAnyPublisher()
    }

    /// Records `count` occurrences of `divergence`, distinguished by `detail`.
    ///
    /// A non-positive `count` records nothing. That shape is a caller bug — a
    /// loop reporting its counter without checking the counter ran — and the
    /// damage it would do is worse than the omission: a row reading "happened
    /// 0 times" is indistinguishable, in a report, from a finding.
    public func record(_ divergence: UpstreamDivergence, detail: String, count: Int = 1) {
        guard count > 0 else { return }

        let key = Key(divergenceID: divergence.id, detail: detail)
        let now = Date()

        lock.lock()
        let existing = rows[key]
        rows[key] = UpstreamDivergenceHit(
            divergence: divergence,
            detail: detail,
            firstSeen: existing?.firstSeen ?? now,
            lastSeen: now,
            count: (existing?.count ?? 0) + count
        )
        lock.unlock()

        if existing == nil {
            Self.logger.info(
                """
                Divergence from VS Code first seen: \(divergence.id, privacy: .public) \
                — \(divergence.ourBehaviour, privacy: .public)
                """
            )
        }
        publish()
    }

    /// Empties the ledger — the "I have read these, show me what the next
    /// thing I try does" button.
    public func clear() {
        lock.lock()
        rows.removeAll()
        lock.unlock()
        publish()
    }

    /// Hands subscribers what the ledger holds *now*.
    ///
    /// **The snapshot is taken inside `publishLock`, and that is the whole
    /// point of this being a method.** Each writer used to compute its snapshot
    /// under `lock` and send it after releasing, which left the order of the
    /// sends to the scheduler: a recorder overtaken in that gap by `clear()`
    /// published rows the clear had already removed. `CurrentValueSubject`
    /// keeps the last value it is handed and gives it to every later
    /// subscriber, so that is not a flicker — the panel goes on showing hits
    /// `hits` says are gone, until the next one arrives, which may be never.
    /// Reading the rows inside the publishing exclusion means whoever sends
    /// last sends the newest state, whatever order the writers arrived in.
    ///
    /// Two locks rather than one because sending under `lock` would run every
    /// subscriber's sink with it held, and a sink that so much as read `hits`
    /// would deadlock against itself. The one rule this leaves is narrow and
    /// worth stating: **a subscriber must not record into the same ledger from
    /// inside its sink.** Nothing does; the settings panel reads the rows and
    /// draws them.
    private func publish() {
        publishLock.lock()
        defer { publishLock.unlock() }

        lock.lock()
        let snapshot = Self.sorted(rows)
        lock.unlock()

        subject.send(snapshot)
    }

    private static func sorted(_ rows: [Key: UpstreamDivergenceHit]) -> [UpstreamDivergenceHit] {
        rows.values.sorted {
            ($0.divergence.id, $0.detail) < ($1.divergence.id, $1.detail)
        }
    }
}

extension UpstreamDivergenceLedger: Loggable {
    public static nonisolated let logger = makeLogger()
}
