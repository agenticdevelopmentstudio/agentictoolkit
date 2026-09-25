import XCTest
@testable import AgenticToolkitCore

/// The shared billing client over a scripted transport: what it sends, how
/// long it waits, and how it reads each kind of reply.
final class BillingXPCClientTests: XCTestCase {

    struct Refusal: Error, BillingRefusalReason {
        let reason: String?
    }

    struct Unreachable: Error {}

    /// Answers every call from its scripted replies and records the timeout
    /// and retries each call asked for.
    final class ScriptedTransport: BillingXPCTransport, @unchecked Sendable {
        var rows: [Data] = []
        var count = 0
        var data = Data()
        var refusableData: Result<Data, Refusal> = .success(Data())
        var refusable: Result<Void, Refusal> = .success(())
        var unreachable = false
        private(set) var calls: [(timeout: TimeInterval??, retries: Int)] = []

        private func record(_ timeout: TimeInterval??, _ retries: Int) throws {
            calls.append((timeout, retries))
            if unreachable { throw Unreachable() }
        }

        func callDecoding<T: Decodable>(
            _ type: T.Type, timeout: TimeInterval??, retries: Int,
            _ invoke: @escaping @Sendable (Proxy, @escaping @Sendable (Data) -> Void) -> Void
        ) async throws -> T {
            try record(timeout, retries)
            return try BillingXPCClient<ScriptedTransport>.makeReplyDecoder().decode(T.self, from: data)
        }

        func callDecodingArray<T: Decodable>(
            _ type: T.Type, timeout: TimeInterval??, retries: Int,
            _ invoke: @escaping @Sendable (Proxy, @escaping @Sendable ([Data]) -> Void) -> Void
        ) async throws -> [T] {
            try record(timeout, retries)
            let decoder = BillingXPCClient<ScriptedTransport>.makeReplyDecoder()
            return try rows.map { try decoder.decode(T.self, from: $0) }
        }

        func callData(
            timeout: TimeInterval??, retries: Int,
            _ invoke: @escaping @Sendable (Proxy, @escaping @Sendable (Data) -> Void) -> Void
        ) async throws -> Data {
            try record(timeout, retries)
            return data
        }

        func callInt(
            timeout: TimeInterval??, retries: Int,
            _ invoke: @escaping @Sendable (Proxy, @escaping @Sendable (Int) -> Void) -> Void
        ) async throws -> Int {
            try record(timeout, retries)
            return count
        }

        func callRefusableData(
            timeout: TimeInterval??, retries: Int,
            _ invoke: @escaping @Sendable (Proxy, @escaping @Sendable (Data?, String?) -> Void) -> Void
        ) async throws -> Result<Data, Refusal> {
            try record(timeout, retries)
            return refusableData
        }

        func callRefusable(
            timeout: TimeInterval??, retries: Int,
            _ invoke: @escaping @Sendable (Proxy, @escaping @Sendable (Bool, String?) -> Void) -> Void
        ) async throws -> Result<Void, Refusal> {
            try record(timeout, retries)
            return refusable
        }
    }

    private let transport = ScriptedTransport()

    /// `value` as the daemon sends it: snake-case keys.
    private func wire(_ value: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return (try? encoder.encode(value)) ?? Data()
    }
    private lazy var client = BillingXPCClient(transport: transport)

    /// The daemon holds a write for up to 60 s and never takes back a message
    /// it was sent. A client that gives up first reports a write that then
    /// commits as a failure.
    func testAWriteWaitsOutTheDaemonsOwnWriteBoundAndIsNeverRetried() async {
        XCTAssertGreaterThan(BillingXPCClient<ScriptedTransport>.writeTimeout, 60)
        transport.refusableData = .success(wire(BillingClientDTO(id: "c1", name: "Acme")))
        _ = await client.billingSaveClient(BillingClientDTO(id: "c1", name: "Acme"))
        XCTAssertEqual(transport.calls.last?.timeout, .some(.some(BillingXPCClient<ScriptedTransport>.writeTimeout)))
        XCTAssertEqual(transport.calls.last?.retries, 0)
    }

    func testAWriteAnswersTheStoredValue() async {
        transport.refusableData = .success(wire(BillingClientDTO(id: "c1", name: "Acme Corp")))
        let result = await client.billingSaveClient(BillingClientDTO(id: "c1", name: "Acme"))
        XCTAssertEqual(try? result.get().name, "Acme Corp")
    }

    func testARefusalCarriesTheStoresSentence() async {
        transport.refusableData = .failure(Refusal(reason: "Rounding must be at least one minute."))
        let result = await client.billingSaveProject(BillingProjectDTO(id: "p1", name: "Site"))
        XCTAssertEqual(result.failure, BillingRefusal(message: "Rounding must be at least one minute."))

        transport.refusable = .failure(Refusal(reason: nil))
        let deleted = await client.billingDeleteClient(id: "c1")
        XCTAssertEqual(deleted.failure, BillingRefusal(message: nil))
        XCTAssertEqual(BillingRefusal(message: nil).message, "The daemon refused the change.")
    }

    func testAnUnreachableDaemonAndAnUnreadableReplyAreTheirOwnRefusals() async {
        transport.refusableData = .success(Data("not json".utf8))
        let unreadable = await client.billingStopTimer(id: "s1")
        XCTAssertEqual(unreadable.failure, .unreadable)

        transport.unreachable = true
        let unreachable = await client.billingStopTimer(id: "s1")
        XCTAssertEqual(unreachable.failure, .unreachable)
    }

    /// A failed read is never "none": a read-failed row makes the whole list nil.
    func testAListWithAReadFailedRowIsNil() async {
        transport.rows = [wire(BillingClientDTO(id: "c1", name: "Acme"))]
        let clients = await client.billingClients()
        XCTAssertEqual(clients?.map(\.id), ["c1"])

        transport.rows.append(Data(#"{"billing_read_failed":true}"#.utf8))
        let failed = await client.billingClients()
        XCTAssertNil(failed)
    }

    func testANegativeCountIsAFailedWrite() async {
        transport.count = 3
        let moved = await client.billingAssignSegments(ids: ["s1"], projectId: "p1")
        XCTAssertEqual(moved, 3)
        transport.count = -1
        let failed = await client.billingPromoteSegments(ids: ["s1"])
        XCTAssertNil(failed)
    }

    func testPreferencesAreAppliedOnlyWhenTheReplyIsNotEmpty() async {
        transport.data = Data()
        let empty = await client.billingSetPreferences(Data("{}".utf8))
        XCTAssertFalse(empty)
        transport.data = Data("{}".utf8)
        let applied = await client.billingSetPreferences(Data("{}".utf8))
        XCTAssertTrue(applied)
    }

    /// One factory for the reply decoder, so the reads the transport decodes
    /// and the writes that decode their own replies can't read the wire two ways.
    func testTheReplyDecoderReadsTheDaemonsWireFormat() throws {
        struct Reply: Decodable, Equatable {
            let projectId: String
            let startedAt: Date
        }
        let json = Data(#"{"project_id":"p1","started_at":"2026-09-22T09:00:00Z"}"#.utf8)
        let reply = try BillingXPCClient<ScriptedTransport>.makeReplyDecoder().decode(Reply.self, from: json)
        XCTAssertEqual(reply, Reply(projectId: "p1", startedAt: Date(timeIntervalSince1970: 1_790_067_600)))
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
