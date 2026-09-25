import Foundation

// MARK: - Service

/// Why a billing write didn't take, in a sentence fit for an alert. The
/// store's own refusals come through verbatim; the two statics cover what
/// happens before or after the store gets a say.
public struct BillingRefusal: Error, Equatable, Sendable {
    public let message: String

    /// nil from the wire means the store refused without a reason — the
    /// last-resort wording, not a common path.
    public init(message: String?) {
        self.message = message ?? "The daemon refused the change."
    }

    public static let unreachable = BillingRefusal(message: "The daemon isn't answering.")
    public static let unreadable = BillingRefusal(message: "The daemon's reply couldn't be read.")
}

/// Everything an app can ask of billing. ``BillingModel`` is written against
/// this, so a window, a command-line tool and a test fake all drive the same
/// model; ``BillingXPCClient`` is the implementation that talks to a daemon.
///
/// Reads answer nil when they failed — a failed read is never "none". Writes
/// answer the stored value, or the refusal that says why nothing was stored.
public protocol BillingService: Sendable {
    func billingClients() async -> [BillingClientDTO]?
    func billingSaveClient(_ client: BillingClientDTO) async -> Result<BillingClientDTO, BillingRefusal>
    @discardableResult
    func billingDeleteClient(id: String) async -> Result<Void, BillingRefusal>

    func billingProjects() async -> [BillingProjectDTO]?
    func billingSaveProject(_ project: BillingProjectDTO) async -> Result<BillingProjectDTO, BillingRefusal>
    @discardableResult
    func billingDeleteProject(id: String) async -> Result<Void, BillingRefusal>

    func billingRepos(projectId: String) async -> [BillingRepoDTO]?
    func billingSaveRepo(_ repo: BillingRepoDTO) async -> Result<BillingRepoDTO, BillingRefusal>
    @discardableResult
    func billingDeleteRepo(id: String) async -> Result<Void, BillingRefusal>

    /// Newest day first. nil filters mean "any"; `since` is an ISO day.
    func billingEntries(projectId: String?, status: BillingStatus?, since: String?) async -> [BillingEntryDTO]?
    func billingSaveEntry(_ entry: BillingEntryDTO) async -> Result<BillingEntryDTO, BillingRefusal>
    func billingSetEntryStatus(id: String, status: BillingStatus) async -> Result<BillingEntryDTO, BillingRefusal>
    /// Only the words change; the entry's figures stay the store's.
    func billingSetEntryDescription(id: String, description: String) async -> Result<BillingEntryDTO, BillingRefusal>
    @discardableResult
    func billingDeleteEntry(id: String) async -> Result<Void, BillingRefusal>
    func billingEntryAudit(entryId: String) async -> [BillingAuditDTO]?

    func billingSegments(since: String?, limit: Int) async -> [BillingSegmentDTO]?
    func billingRunningTimers() async -> [BillingSegmentDTO]?
    func billingStartTimer(_ start: BillingTimerStartDTO) async -> Result<BillingSegmentDTO, BillingRefusal>
    func billingStopTimer(id: String) async -> Result<BillingSegmentDTO, BillingRefusal>

    /// How many segments moved; nil when the write failed.
    func billingAssignSegments(ids: [String], projectId: String?) async -> Int?
    func billingPromoteSegments(ids: [String]) async -> Int?
    /// How many of the repository's loose segments moved into the project.
    func billingAssignRepository(projectRoot: String, projectId: String) async -> Int?
    /// How many sessions were queued for derivation.
    func billingBackfill(since: String) async -> Int?
    func billingOverview() async -> BillingOverviewDTO?

    /// Pushes the full billing knobs snapshot (the host's
    /// ``BillingSettingsKeys``, all values strings); true when it was applied.
    @discardableResult
    func billingSetPreferences(_ body: Data) async -> Bool
}

extension BillingService {
    /// A service with no settings to push — a read-only tool, a test fake —
    /// reports every push as not applied.
    @discardableResult
    public func billingSetPreferences(_ body: Data) async -> Bool { false }
}

// MARK: - Transport

/// What a transport's refusal must say: the sentence the store refused with,
/// or nil when it gave none.
public protocol BillingRefusalReason {
    var reason: String? { get }
}

/// The calls ``BillingXPCClient`` makes, in the shape DaemonKit's
/// `XPCClient<any BillingXPCProtocol>` already has — a leaf declares
/// `extension XPCClient: @retroactive BillingXPCTransport where Proxy == any
/// BillingXPCProtocol {}` and passes its client in. Stated here rather than
/// imported so this tier depends on no daemon framework, and any transport
/// that can answer these (an in-process test double) can stand in.
public protocol BillingXPCTransport: Sendable {
    associatedtype Refusal: Error & BillingRefusalReason
    typealias Proxy = any BillingXPCProtocol

    func callDecoding<T: Decodable>(
        _ type: T.Type, timeout: TimeInterval??, retries: Int,
        _ invoke: @escaping @Sendable (Proxy, @escaping @Sendable (Data) -> Void) -> Void
    ) async throws -> T

    func callDecodingArray<T: Decodable>(
        _ type: T.Type, timeout: TimeInterval??, retries: Int,
        _ invoke: @escaping @Sendable (Proxy, @escaping @Sendable ([Data]) -> Void) -> Void
    ) async throws -> [T]

    func callData(
        timeout: TimeInterval??, retries: Int,
        _ invoke: @escaping @Sendable (Proxy, @escaping @Sendable (Data) -> Void) -> Void
    ) async throws -> Data

    func callInt(
        timeout: TimeInterval??, retries: Int,
        _ invoke: @escaping @Sendable (Proxy, @escaping @Sendable (Int) -> Void) -> Void
    ) async throws -> Int

    func callRefusableData(
        timeout: TimeInterval??, retries: Int,
        _ invoke: @escaping @Sendable (Proxy, @escaping @Sendable (Data?, String?) -> Void) -> Void
    ) async throws -> Result<Data, Refusal>

    func callRefusable(
        timeout: TimeInterval??, retries: Int,
        _ invoke: @escaping @Sendable (Proxy, @escaping @Sendable (Bool, String?) -> Void) -> Void
    ) async throws -> Result<Void, Refusal>
}

// MARK: - Client

/// ``BillingService`` over XPC to a daemon that exports ``BillingXPCProtocol``.
///
/// Usable from any process — an app, a Swift command-line tool — because all it
/// needs is a transport: build a DaemonKit `XPCClient` with
/// `NSXPCInterface(with: BillingXPCProtocol.self)` and
/// ``makeReplyDecoder()``, and pass it in.
public final class BillingXPCClient<Transport: BillingXPCTransport>: BillingService {

    /// How long a billing write waits for its answer. Longer than a daemon's
    /// own 60 s bound on a write: the message is never taken back once sent,
    /// so a write that waited behind another for longer than the client did
    /// still commits — and was reported to the user as a failure. Waiting out
    /// the daemon's bound means a timeout here is a daemon that truly did not
    /// answer.
    public static var writeTimeout: TimeInterval { 65 }

    /// The one JSON reading of a billing reply: snake case, ISO-8601 dates.
    /// The transport decodes with it, and so do the writes that decode their
    /// own replies, so the two can't read the wire differently.
    public static func makeReplyDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public let transport: Transport
    private let replyDecoder = BillingXPCClient.makeReplyDecoder()

    public init(transport: Transport) {
        self.transport = transport
    }

    // MARK: Wire helpers

    /// Save bodies go over in the daemon's own key style.
    private static func body<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try? encoder.encode(value)
    }

    /// One billing write: the stored value, or the sentence saying why the
    /// daemon refused — so an alert can say "Rounding must be at least one
    /// minute" instead of only "couldn't save".
    private func write<T: Decodable>(
        _ type: T.Type,
        _ invoke: @escaping @Sendable (Transport.Proxy, @escaping @Sendable (Data?, String?) -> Void) -> Void
    ) async -> Result<T, BillingRefusal> {
        let reply: Result<Data, Transport.Refusal>
        do {
            reply = try await transport.callRefusableData(timeout: Self.writeTimeout, retries: 0, invoke)
        } catch {
            return .failure(.unreachable)
        }
        switch reply {
        case .failure(let refusal):
            return .failure(BillingRefusal(message: refusal.reason))
        case .success(let data):
            guard let value = try? replyDecoder.decode(T.self, from: data) else { return .failure(.unreadable) }
            return .success(value)
        }
    }

    /// An encodable body's write; an unencodable body never leaves.
    private func write<Body: Encodable, T: Decodable>(
        _ body: Body, as type: T.Type,
        _ invoke: @escaping @Sendable (Transport.Proxy, Data, @escaping @Sendable (Data?, String?) -> Void) -> Void
    ) async -> Result<T, BillingRefusal> {
        guard let data = Self.body(body) else { return .failure(.unreadable) }
        return await write(type) { invoke($0, data, $1) }
    }

    /// The delete counterpart of `write`: success, or why not.
    private func delete(
        _ invoke: @escaping @Sendable (Transport.Proxy, @escaping @Sendable (Bool, String?) -> Void) -> Void
    ) async -> Result<Void, BillingRefusal> {
        do {
            return try await transport.callRefusable(timeout: Self.writeTimeout, retries: 0, invoke)
                .mapError { BillingRefusal(message: $0.reason) }
        } catch {
            return .failure(.unreachable)
        }
    }

    /// A list read: the rows, or nil when the daemon is unreachable or
    /// replied `BillingWire.readFailedRow` — a failed read is never "none".
    private func list<T: Decodable>(
        _ type: T.Type,
        _ invoke: @escaping @Sendable (Transport.Proxy, @escaping @Sendable ([Data]) -> Void) -> Void
    ) async -> [T]? {
        guard let rows = try? await transport.callDecodingArray(
            BillingListRow<T>.self, timeout: nil, retries: 0, invoke
        ) else { return nil }
        var values: [T] = []
        for row in rows {
            switch row {
            case .value(let value): values.append(value)
            case .readFailed: return nil
            }
        }
        return values
    }

    /// A count write: the count, or nil when the daemon is unreachable or
    /// replied `BillingWire.failedCount`.
    private func count(
        _ invoke: @escaping @Sendable (Transport.Proxy, @escaping @Sendable (Int) -> Void) -> Void
    ) async -> Int? {
        guard let count = try? await transport.callInt(timeout: Self.writeTimeout, retries: 0, invoke),
              count >= 0 else { return nil }
        return count
    }

    // MARK: Clients

    public func billingClients() async -> [BillingClientDTO]? {
        await list(BillingClientDTO.self) { $0.billingClients(reply: $1) }
    }

    public func billingSaveClient(_ client: BillingClientDTO) async -> Result<BillingClientDTO, BillingRefusal> {
        await write(client, as: BillingClientDTO.self) { $0.billingSaveClient($1, reply: $2) }
    }

    @discardableResult
    public func billingDeleteClient(id: String) async -> Result<Void, BillingRefusal> {
        await delete { $0.billingDeleteClient(id, reply: $1) }
    }

    // MARK: Projects

    public func billingProjects() async -> [BillingProjectDTO]? {
        await list(BillingProjectDTO.self) { $0.billingProjects(reply: $1) }
    }

    public func billingSaveProject(_ project: BillingProjectDTO) async -> Result<BillingProjectDTO, BillingRefusal> {
        await write(project, as: BillingProjectDTO.self) { $0.billingSaveProject($1, reply: $2) }
    }

    @discardableResult
    public func billingDeleteProject(id: String) async -> Result<Void, BillingRefusal> {
        await delete { $0.billingDeleteProject(id, reply: $1) }
    }

    // MARK: Repos

    public func billingRepos(projectId: String) async -> [BillingRepoDTO]? {
        await list(BillingRepoDTO.self) { $0.billingRepos(projectId: projectId, reply: $1) }
    }

    public func billingSaveRepo(_ repo: BillingRepoDTO) async -> Result<BillingRepoDTO, BillingRefusal> {
        await write(repo, as: BillingRepoDTO.self) { $0.billingSaveRepo($1, reply: $2) }
    }

    @discardableResult
    public func billingDeleteRepo(id: String) async -> Result<Void, BillingRefusal> {
        await delete { $0.billingDeleteRepo(id, reply: $1) }
    }

    // MARK: Entries

    public func billingEntries(
        projectId: String?, status: BillingStatus?, since: String?
    ) async -> [BillingEntryDTO]? {
        await list(BillingEntryDTO.self) {
            $0.billingEntries(projectId: projectId, status: status?.rawValue, since: since, reply: $1)
        }
    }

    /// Refused when the entry is billed/paid (locked), when the save would
    /// move its status, or when the daemon is unreachable.
    public func billingSaveEntry(_ entry: BillingEntryDTO) async -> Result<BillingEntryDTO, BillingRefusal> {
        await write(entry, as: BillingEntryDTO.self) { $0.billingSaveEntry($1, reply: $2) }
    }

    public func billingSetEntryStatus(
        id: String, status: BillingStatus
    ) async -> Result<BillingEntryDTO, BillingRefusal> {
        await write(BillingEntryDTO.self) { $0.billingSetEntryStatus(id, status: status.rawValue, reply: $1) }
    }

    public func billingSetEntryDescription(
        id: String, description: String
    ) async -> Result<BillingEntryDTO, BillingRefusal> {
        await write(BillingEntryDTO.self) { $0.billingSetEntryDescription(id, description: description, reply: $1) }
    }

    @discardableResult
    public func billingDeleteEntry(id: String) async -> Result<Void, BillingRefusal> {
        await delete { $0.billingDeleteEntry(id, reply: $1) }
    }

    public func billingEntryAudit(entryId: String) async -> [BillingAuditDTO]? {
        await list(BillingAuditDTO.self) { $0.billingEntryAudit(entryId, reply: $1) }
    }

    // MARK: Segments and timers

    public func billingSegments(since: String?, limit: Int) async -> [BillingSegmentDTO]? {
        await list(BillingSegmentDTO.self) { $0.billingSegments(since: since, limit: limit, reply: $1) }
    }

    public func billingRunningTimers() async -> [BillingSegmentDTO]? {
        await list(BillingSegmentDTO.self) { $0.billingRunningTimers(reply: $1) }
    }

    public func billingStartTimer(_ start: BillingTimerStartDTO) async -> Result<BillingSegmentDTO, BillingRefusal> {
        await write(start, as: BillingSegmentDTO.self) { $0.billingStartTimer($1, reply: $2) }
    }

    public func billingStopTimer(id: String) async -> Result<BillingSegmentDTO, BillingRefusal> {
        await write(BillingSegmentDTO.self) { $0.billingStopTimer(id, reply: $1) }
    }

    // MARK: Counts

    public func billingAssignSegments(ids: [String], projectId: String?) async -> Int? {
        await count { $0.billingAssignSegments(ids, projectId: projectId, reply: $1) }
    }

    public func billingPromoteSegments(ids: [String]) async -> Int? {
        await count { $0.billingPromoteSegments(ids, reply: $1) }
    }

    public func billingAssignRepository(projectRoot: String, projectId: String) async -> Int? {
        await count { $0.billingAssignRepository(projectRoot, projectId: projectId, reply: $1) }
    }

    public func billingBackfill(since: String) async -> Int? {
        await count { $0.billingBackfill(since: since, reply: $1) }
    }

    // MARK: Overview and preferences

    public func billingOverview() async -> BillingOverviewDTO? {
        try? await transport.callDecoding(BillingOverviewDTO.self, timeout: nil, retries: 0) {
            $0.billingOverview(reply: $1)
        }
    }

    @discardableResult
    public func billingSetPreferences(_ body: Data) async -> Bool {
        // Empty data is the daemon saying the write failed — not applied.
        let reply = try? await transport.callData(timeout: 5, retries: 0) { $0.billingSetPreferences(body, reply: $1) }
        return reply?.isEmpty == false
    }
}

/// One element of a billing list reply: a row, or `BillingWire.readFailedRow`.
enum BillingListRow<T: Decodable>: Decodable {
    case value(T)
    case readFailed

    /// The reply decoder reads snake case, so the sentinel's key arrives
    /// camel-cased.
    private enum Key: String, CodingKey { case billingReadFailed }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: Key.self),
           (try? container.decode(Bool.self, forKey: .billingReadFailed)) == true {
            self = .readFailed
        } else {
            self = .value(try T(from: decoder))
        }
    }
}
