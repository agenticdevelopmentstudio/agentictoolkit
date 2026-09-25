import Foundation

/// Where a billable row is in its life. Three states, one direction: the
/// feature tracks time and keeps billing organized — the actual invoicing
/// happens in the client's own tool, so there is no invoice entity to model.
public enum BillingStatus: String, Codable, Sendable, CaseIterable {
    case unbilled
    case billed
    case paid

    /// The next state forward, or nil at the end. Advancing is always an
    /// explicit user action; nothing derives it.
    public var next: BillingStatus? {
        switch self {
        case .unbilled: return .billed
        case .billed: return .paid
        case .paid: return nil
        }
    }

    /// Anything past `unbilled` freezes the entry: derivation must never
    /// recompute a row whose figure has already been given to someone.
    public var locksTheEntry: Bool { self != .unbilled }
}

/// A client. Contact fields are all optional in practice and carry `""` when
/// unset, so the app's form bindings never unwrap.
public struct BillingClientDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let contactName: String
    public let email: String
    public let phone: String
    public let url: String
    public let notes: String
    /// ISO-4217. Every project under this client inherits it.
    public let currency: String
    public let archived: Bool
    public let createdAt: String
    public let updatedAt: String

    public init(
        id: String,
        name: String,
        contactName: String = "",
        email: String = "",
        phone: String = "",
        url: String = "",
        notes: String = "",
        currency: String = "USD",
        archived: Bool = false,
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.name = name
        self.contactName = contactName
        self.email = email
        self.phone = phone
        self.url = url
        self.notes = notes
        self.currency = currency
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A project. `clientId` is nil for your own work.
public struct BillingProjectDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let clientId: String?
    public let name: String
    public let notes: String
    /// nil = fall through to the global default rate.
    public let defaultRateCents: Int?
    public let roundingMinutes: Int
    /// `"up"` or `"nearest"`.
    public let roundingMode: String
    public let billingEnabled: Bool
    public let archived: Bool
    public let createdAt: String
    public let updatedAt: String

    public init(
        id: String,
        clientId: String? = nil,
        name: String,
        notes: String = "",
        defaultRateCents: Int? = nil,
        roundingMinutes: Int = 15,
        roundingMode: String = "up",
        billingEnabled: Bool = true,
        archived: Bool = false,
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.clientId = clientId
        self.name = name
        self.notes = notes
        self.defaultRateCents = defaultRateCents
        self.roundingMinutes = roundingMinutes
        self.roundingMode = roundingMode
        self.billingEnabled = billingEnabled
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// The join between billing and reality: a repo path (and optionally one
/// branch) belonging to a project. `branch == ""` means any branch.
public struct BillingRepoDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let projectId: String
    /// Absolute path, matching `sessions.project_root`.
    public let projectRoot: String
    public let branch: String
    /// nil = inherit the project's default rate.
    public let rateCents: Int?
    public let billingEnabled: Bool
    public let createdAt: String
    public let updatedAt: String

    public init(
        id: String,
        projectId: String,
        projectRoot: String,
        branch: String = "",
        rateCents: Int? = nil,
        billingEnabled: Bool = true,
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.projectId = projectId
        self.projectRoot = projectRoot
        self.branch = branch
        self.rateCents = rateCents
        self.billingEnabled = billingEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One continuous stretch of tracked time. `origin` is `"auto"` (derived from
/// session activity) or `"manual"` (a timer someone started). A nil
/// `projectId` is the Unassigned bucket — time in a repo no project claims.
public struct BillingSegmentDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    /// Empty for a manual timer.
    public let sessionId: String
    public let origin: String
    public let projectId: String?
    public let repoId: String?
    public let projectRoot: String
    public let branch: String
    public let startedAt: String
    /// Empty while running.
    public let endedAt: String
    // swiftlint:disable identifier_name
    /// IANA zone captured when the segment was created — local-day bucketing
    /// uses this, not the reader's current zone.
    public let tz: String
    // swiftlint:enable identifier_name
    public let seconds: Int
    public let note: String
    /// Set once the segment has been rolled into an entry.
    public let entryId: String?
    /// Comma-separated markers, e.g. `"runaway"`.
    public let flags: String
    public let createdAt: String
    public let updatedAt: String

    public var isRunning: Bool { endedAt.isEmpty }

    /// `origin` for time derived from session activity.
    public static let autoOrigin = "auto"
    /// `origin` for a timer someone started. The one spelling every check
    /// uses: `origin` is a plain wire string, so a typo in a copy would
    /// compile and quietly never match.
    public static let manualOrigin = "manual"

    /// A timer someone started, which only they can stop.
    public var isManual: Bool { origin == Self.manualOrigin }

    public init(
        id: String,
        sessionId: String = "",
        origin: String,
        projectId: String? = nil,
        repoId: String? = nil,
        projectRoot: String = "",
        branch: String = "",
        startedAt: String,
        endedAt: String = "",
        // swiftlint:disable:next identifier_name
        tz: String = "",
        seconds: Int = 0,
        note: String = "",
        entryId: String? = nil,
        flags: String = "",
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.sessionId = sessionId
        self.origin = origin
        self.projectId = projectId
        self.repoId = repoId
        self.projectRoot = projectRoot
        self.branch = branch
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.tz = tz
        self.seconds = seconds
        self.note = note
        self.entryId = entryId
        self.flags = flags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A billable row. Rate, currency and rounding are **snapshotted** here at write
/// time; changing a project's rate later never rewrites history.
public struct BillingEntryDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let projectId: String
    /// Denormalised at write time so a reassigned project can't relabel a
    /// figure already sent to a client.
    public let clientId: String?
    /// Local calendar day, `YYYY-MM-DD`, in the segment's own zone.
    public let day: String
    /// What this entry groups. At day granularity `""` for time at the
    /// project's own rate and `rate:<cents>` for time a repo bills at a
    /// different rate — one entry per project, day and rate. At run
    /// granularity `<session_id>|<started_at>` for a derived run (its stable
    /// identity) or the segment id for a manual timer. Part of the uniqueness
    /// key so switching granularity doesn't collide.
    public let groupKey: String
    public let startedAt: String
    public let endedAt: String
    /// Time actually tracked, before rounding. Always kept.
    public let rawSeconds: Int
    /// What is charged for, after rounding once at entry level.
    public let billedSeconds: Int
    public let rateCents: Int
    public let currency: String
    public let amountCents: Int
    public let roundingMinutes: Int
    public let roundingMode: String
    /// One of `BillingStatus`.
    public let status: String
    public let description: String
    public let origin: String
    public let locked: Bool
    /// Set when this entry covers time that landed after a frozen day was
    /// already billed.
    public let supplementsEntryId: String?
    public let createdAt: String
    public let updatedAt: String

    public init(
        id: String,
        projectId: String,
        clientId: String? = nil,
        day: String,
        groupKey: String = "",
        startedAt: String = "",
        endedAt: String = "",
        rawSeconds: Int,
        billedSeconds: Int,
        rateCents: Int,
        currency: String = "USD",
        amountCents: Int,
        roundingMinutes: Int = 15,
        roundingMode: String = "up",
        status: String = BillingStatus.unbilled.rawValue,
        description: String = "",
        origin: String = "auto",
        locked: Bool = false,
        supplementsEntryId: String? = nil,
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.projectId = projectId
        self.clientId = clientId
        self.day = day
        self.groupKey = groupKey
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.rawSeconds = rawSeconds
        self.billedSeconds = billedSeconds
        self.rateCents = rateCents
        self.currency = currency
        self.amountCents = amountCents
        self.roundingMinutes = roundingMinutes
        self.roundingMode = roundingMode
        self.status = status
        self.description = description
        self.origin = origin
        self.locked = locked
        self.supplementsEntryId = supplementsEntryId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One status bucket of the overview.
public struct BillingOverviewBucketDTO: Codable, Sendable, Equatable {
    public let seconds: Int
    public let amountCents: Int
    public let entryCount: Int

    public init(seconds: Int, amountCents: Int, entryCount: Int) {
        self.seconds = seconds
        self.amountCents = amountCents
        self.entryCount = entryCount
    }
}

/// One currency's unbilled / billed / paid figures.
public struct BillingOverviewCurrencyDTO: Codable, Sendable, Equatable {
    public let currency: String
    public let unbilled: BillingOverviewBucketDTO
    public let billed: BillingOverviewBucketDTO
    public let paid: BillingOverviewBucketDTO

    public init(
        currency: String,
        unbilled: BillingOverviewBucketDTO,
        billed: BillingOverviewBucketDTO,
        paid: BillingOverviewBucketDTO
    ) {
        self.currency = currency
        self.unbilled = unbilled
        self.billed = billed
        self.paid = paid
    }
}

/// The unbilled / billed / paid summary the Billing Activity window shows and a
/// person transcribes into the client's tool.
///
/// Amounts are never summed across currencies — there is no conversion
/// anywhere, so €100 + $100 is not a number. `byCurrency` carries one row per
/// currency in use (most entries first); the top-level buckets and `currency`
/// are that first row's, kept so a reader that only knows one currency still
/// reads a true figure rather than a mixed sum.
public struct BillingOverviewDTO: Codable, Sendable, Equatable {
    public let unbilled: BillingOverviewBucketDTO
    public let billed: BillingOverviewBucketDTO
    public let paid: BillingOverviewBucketDTO
    public let currency: String
    public let byCurrency: [BillingOverviewCurrencyDTO]

    public init(
        unbilled: BillingOverviewBucketDTO,
        billed: BillingOverviewBucketDTO,
        paid: BillingOverviewBucketDTO,
        currency: String = "USD",
        byCurrency: [BillingOverviewCurrencyDTO] = []
    ) {
        self.unbilled = unbilled
        self.billed = billed
        self.paid = paid
        self.currency = currency
        self.byCurrency = byCurrency
    }

    private enum CodingKeys: String, CodingKey {
        case unbilled, billed, paid, currency, byCurrency
    }

    /// `byCurrency` is optional on the wire so a reply from a daemon that
    /// predates it still decodes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unbilled = try container.decode(BillingOverviewBucketDTO.self, forKey: .unbilled)
        billed = try container.decode(BillingOverviewBucketDTO.self, forKey: .billed)
        paid = try container.decode(BillingOverviewBucketDTO.self, forKey: .paid)
        currency = try container.decode(String.self, forKey: .currency)
        byCurrency = try container.decodeIfPresent([BillingOverviewCurrencyDTO].self, forKey: .byCurrency) ?? []
    }
}

/// What the app sends to start a manual timer.
public struct BillingTimerStartDTO: Codable, Sendable, Equatable {
    public let projectId: String?
    public let repoId: String?
    public let projectRoot: String
    public let branch: String
    public let note: String

    public init(
        projectId: String? = nil,
        repoId: String? = nil,
        projectRoot: String = "",
        branch: String = "",
        note: String = ""
    ) {
        self.projectId = projectId
        self.repoId = repoId
        self.projectRoot = projectRoot
        self.branch = branch
        self.note = note
    }
}

/// One recorded change to an entry. Append-only: the audit exists so a figure
/// that moved can be explained months later, which means it must be readable,
/// not merely written — Task 20 shows it under the entry editor.
public struct BillingAuditDTO: Codable, Sendable, Equatable {
    public let entryId: String
    // swiftlint:disable:next identifier_name
    public let at: String
    public let field: String
    public let oldValue: String
    public let newValue: String
    /// `auto` (the rollup) or `user`.
    public let source: String

    public init(
        entryId: String,
        // swiftlint:disable:next identifier_name
        at: String,
        field: String,
        oldValue: String = "",
        newValue: String = "",
        source: String = "user"
    ) {
        self.entryId = entryId
        self.at = at
        self.field = field
        self.oldValue = oldValue
        self.newValue = newValue
        self.source = source
    }
}

/// How a billing reply says "that failed" where its type has no nil.
public enum BillingWire {
    /// The snake-case key of the one-element list a failed list read replies.
    public static let readFailedKey = "billing_read_failed"
    /// The whole element: `{"billing_read_failed":true}`.
    public static let readFailedRow = Data("{\"\(readFailedKey)\":true}".utf8)
    /// The count a failed assign, promote or backfill replies.
    public static let failedCount = -1
}

/// The settings-table keys the writer of the billing knobs and their reader
/// share. Built from one prefix so each app keeps its knobs in its own
/// namespace ("stenographer_billing_…") while the key *names* are spelled once:
/// a typo on either side is a knob that silently stops working.
public struct BillingSettingsKeys: Sendable, Equatable {
    /// Prepended to every key, e.g. `"stenographer_billing_"`.
    public let prefix: String

    public init(prefix: String) {
        self.prefix = prefix
    }

    public var idleCutoffMinutes: String { prefix + "idle_cutoff_minutes" }
    public var granularity: String { prefix + "granularity" }
    public var roundingMinutes: String { prefix + "rounding_minutes" }
    public var roundingMode: String { prefix + "rounding_mode" }
    public var defaultRateCents: String { prefix + "default_rate_cents" }
    public var currency: String { prefix + "currency" }
    public var manualTimerCapHours: String { prefix + "manual_timer_cap_hours" }
    public var trackUnassigned: String { prefix + "track_unassigned" }

    /// The allow-list `billingSetPreferences` filters an incoming body
    /// through, so a push can only ever write billing keys.
    public var all: Set<String> {
        [
            idleCutoffMinutes, granularity, roundingMinutes, roundingMode,
            defaultRateCents, currency, manualTimerCapHours, trackUnassigned
        ]
    }
}

/// The snapshot `billingSetPreferences` replies: what the daemon holds after a
/// push, clamped. Encoded `.convertToSnakeCase`, so the keys are the settings
/// keys minus their prefix.
public struct BillingPreferencesDTO: Codable, Sendable, Equatable {
    public let idleCutoffMinutes: Int
    public let granularity: String
    public let roundingMinutes: Int
    public let roundingMode: String
    public let defaultRateCents: Int
    public let currency: String
    public let manualTimerCapHours: Int
    public let trackUnassigned: Bool

    public init(
        idleCutoffMinutes: Int,
        granularity: String,
        roundingMinutes: Int,
        roundingMode: String,
        defaultRateCents: Int,
        currency: String,
        manualTimerCapHours: Int,
        trackUnassigned: Bool
    ) {
        self.idleCutoffMinutes = idleCutoffMinutes
        self.granularity = granularity
        self.roundingMinutes = roundingMinutes
        self.roundingMode = roundingMode
        self.defaultRateCents = defaultRateCents
        self.currency = currency
        self.manualTimerCapHours = manualTimerCapHours
        self.trackUnassigned = trackUnassigned
    }
}

/// What an unconfigured install behaves like. The app's `UserSetting` defaults
/// and the daemon's fallbacks both read from here, so a daemon that has never
/// been told anything behaves exactly like one just reset.
public enum BillingDefaults {
    public static let idleCutoffMinutes = 15
    public static let granularity = "day"
    public static let roundingMinutes = 15
    public static let roundingMode = "up"
    public static let defaultRateCents = 0
    public static let currency = "USD"
    public static let manualTimerCapHours = 8
    public static let trackUnassigned = true
}

/// Ranges a stored value is clamped into. An out-of-range number reaches the
/// daemon only from an older app or a hand-rolled POST; clamping keeps it a
/// wrong number instead of a wedged task (a zero cutoff would split every
/// keystroke into its own run).
public enum BillingLimits {
    public static let idleCutoffMinutes = 1...480
    public static let roundingMinutes = 1...240
    public static let defaultRateCents = 0...10_000_000
    public static let manualTimerCapHours = 1...24

    public static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// The sentences the daemon refuses a billing write with. They travel to
/// the app verbatim and are shown in an alert, so the daemon's errors and
/// the app's test double both read them from here — one wording, never two
/// copies that drift apart.
public enum BillingRefusalText {
    public static let missingName = "A name is required."
    public static let missingRepoRoot = "A repository needs a path."
    public static let unknownEntry = "That billing entry no longer exists."
    public static let entryIsLocked = "This entry is billed or paid. Move it back to Unbilled before editing it."
    public static let unknownTimer = "That timer no longer exists."
    public static let timerNotRunning = "That timer has already been stopped."

    public static func repoAlreadyClaimed(root: String, branch: String) -> String {
        let scope = branch.isEmpty ? "any branch" : "branch “\(branch)”"
        return "\(root) (\(scope)) already belongs to another project."
    }

    public static func statusChangeNotAllowed(current: String, requested: String) -> String {
        "Saving an entry can't move it from \(current) to \(requested). Change its status instead."
    }
}
