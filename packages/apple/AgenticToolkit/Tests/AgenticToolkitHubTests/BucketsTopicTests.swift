import XCTest
@testable import AgenticToolkitHub
import AgenticToolkitHTDV

final class FakeBucketsDataSource: BucketsDataSource, @unchecked Sendable {
    var buckets: [Bucket]
    var tables: [BucketTable]
    var creates: [BucketCreate] = []
    var updates: [(id: String, input: BucketUpdate)] = []
    var deletes: [String] = []
    var tableCreates: [BucketTableCreate] = []
    var tableUpdates: [(id: String, input: BucketTableUpdate)] = []
    var tableDeletes: [String] = []
    var failure: HubError?

    init(buckets: [Bucket], tables: [BucketTable] = []) { self.buckets = buckets; self.tables = tables }

    func list(ecosystemID: String) async throws -> [Bucket] {
        try check(); return buckets.filter { $0.ecosystemId == ecosystemID }
    }
    func get(id: String) async throws -> Bucket {
        try check()
        guard let bucket = buckets.first(where: { $0.id == id }) else { throw HubError.notFound }
        return bucket
    }
    func create(_ input: BucketCreate) async throws -> Bucket {
        try check(); creates.append(input)
        let bucket = Bucket(
            id: "b-\(buckets.count + 1)", ecosystemId: input.ecosystemId, name: input.name, metadata: input.metadata
        )
        buckets.append(bucket); return bucket
    }
    func update(id: String, _ input: BucketUpdate) async throws -> Bucket {
        try check(); updates.append((id, input))
        guard var bucket = buckets.first(where: { $0.id == id }) else { throw HubError.notFound }
        if let name = input.name { bucket.name = name }
        if let metadata = input.metadata { bucket.metadata = metadata }
        return bucket
    }
    func delete(id: String) async throws { try check(); deletes.append(id); buckets.removeAll { $0.id == id } }
    func tables(ecosystemID: String) async throws -> [BucketTable] {
        try check()
        let ids = Set(buckets.filter { $0.ecosystemId == ecosystemID }.map(\.id))
        return tables.filter { ids.contains($0.bucketId) }
    }
    func createTable(_ input: BucketTableCreate) async throws -> BucketTable {
        try check(); tableCreates.append(input)
        let table = BucketTable(
            id: "t-\(tables.count + 1)", bucketId: input.bucketId, sqlTableName: input.sqlTableName, name: input.name
        )
        tables.append(table); return table
    }
    func updateTable(id: String, _ input: BucketTableUpdate) async throws -> BucketTable {
        try check(); tableUpdates.append((id, input))
        guard var table = tables.first(where: { $0.id == id }) else { throw HubError.notFound }
        if let name = input.name { table.name = name }
        return table
    }
    func deleteTable(id: String) async throws { try check(); tableDeletes.append(id); tables.removeAll { $0.id == id } }
    private func check() throws { if let failure { throw failure } }
}

extension Bucket {
    static func fixture(
        id: String = "b-profile", name: String = "Profile Basics", kind: String = "custom",
        description: String? = "Names and avatars"
    ) -> Bucket {
        Bucket(
            id: id, ecosystemId: "org.acme.shop", name: name, kind: kind,
            metadata: BucketMetadata(description: description),
            createdAt: "2026-09-04T10:00:00.000Z", updatedAt: "2026-09-04T10:00:00.000Z"
        )
    }
}

/// A one-topic rail: the product's topics level holds only the provider under test.
@MainActor
final class SingleTopicRail: EcosystemRail {
    let topic: any EcosystemTopicProvider
    let ecosystem: Ecosystem
    init(topic: any EcosystemTopicProvider, ecosystem: Ecosystem = .fixture()) {
        self.topic = topic; self.ecosystem = ecosystem
    }
    func child(for ecosystem: Ecosystem, path: [HTDVItem]) async throws -> HTDVChild {
        try await topic.child(for: ecosystem, path: path, rail: self)
    }
    /// Convenience: resolve a topic-relative path of raw ids.
    func child(_ ids: [String]) async throws -> HTDVChild {
        try await topic.child(for: ecosystem, path: ids.map { HTDVItem(id: $0, label: $0) }, rail: self)
    }
    func level(_ ids: [String], file: StaticString = #filePath, line: UInt = #line) async throws -> HTDVLevel {
        guard case .level(let level) = try await child(ids) else {
            XCTFail("expected level at \(ids)", file: file, line: line)
            throw HubError.unexpected("not a level")
        }
        return level
    }
    func form(
        _ ids: [String], file: StaticString = #filePath, line: UInt = #line
    ) async throws -> (HTDVDetail, FormViewController) {
        guard case .detail(let detail) = try await child(ids) else {
            XCTFail("expected detail at \(ids)", file: file, line: line)
            throw HubError.unexpected("not a detail")
        }
        // swiftlint:disable:next force_cast
        return (detail, detail.make() as! FormViewController)
    }
}

@MainActor
final class BucketsTopicTests: XCTestCase {
    private func makeRail(_ source: FakeBucketsDataSource) -> SingleTopicRail {
        SingleTopicRail(topic: BucketsTopic(dataSource: source))
    }

    func testDecodesBucketWithMissingKindAndMetadata() throws {
        let json = #"""
        {"id":"b1","ecosystemId":"org.acme.shop","name":"Profile","metadata":null,
        "createdAt":"2026-09-04T10:00:00.000Z","updatedAt":"2026-09-04T10:00:00.000Z"}
        """#
        let bucket = try JSONDecoder().decode(Bucket.self, from: Data(json.utf8))
        XCTAssertEqual(bucket.kind, "custom")
        XCTAssertFalse(bucket.isBuiltIn)
        XCTAssertEqual(bucket.description, "")
    }

    func testTableNameAndCount() {
        XCTAssertEqual(BucketsTopic.tableName(from: "Contact Notes"), "contact_notes")
        XCTAssertEqual(BucketsTopic.tableName(from: "  Órders-2 "), "rders_2")
        XCTAssertEqual(BucketsTopic.tableCount(0), "0 tables")
        XCTAssertEqual(BucketsTopic.tableCount(1), "1 table")
        XCTAssertEqual(BucketsTopic.tableCount(3), "3 tables")
    }

    func testListShowsBucketsWithTableCounts() async throws {
        let source = FakeBucketsDataSource(
            buckets: [
                .fixture(), .fixture(id: "b-orders", name: "Orders"),
                Bucket(id: "b-other", ecosystemId: "org.other", name: "Elsewhere")
            ],
            tables: [
                BucketTable(id: "t1", bucketId: "b-profile", sqlTableName: "contacts", name: "Contacts"),
                BucketTable(id: "t2", bucketId: "b-profile", sqlTableName: "avatars", name: "Avatars")
            ]
        )
        let level = try await makeRail(source).level([])
        XCTAssertEqual(level.id, "buckets-list")
        XCTAssertEqual(level.title, "Buckets")
        XCTAssertEqual(level.items.map(\.label), ["Profile Basics", "Orders"])
        XCTAssertEqual(level.items.map(\.sublabel), ["2 tables", "0 tables"])
        XCTAssertEqual(level.items.map(\.leadsTo), [.list, .list])
        XCTAssertEqual(level.emptyMessage, "No buckets yet.")
        XCTAssertEqual(level.createAction?.title, "New bucket")
    }

    func testCreateFormValidatesAndCreates() async throws {
        let source = FakeBucketsDataSource(buckets: [.fixture()])
        let topic = BucketsTopic(dataSource: source)
        let spec = topic.createSpec(for: .fixture())
        XCTAssertEqual(spec.fields.map(\.key), ["name", "description"])

        let duplicate = FormState(spec: spec)
        duplicate.set(.string("profile basics"), for: "name")
        let duplicateSaved = await duplicate.save()
        XCTAssertFalse(duplicateSaved)
        XCTAssertEqual(duplicate.saveError, "A bucket named \"profile basics\" already exists.")

        let fresh = FormState(spec: spec)
        fresh.set(.string("Orders"), for: "name")
        fresh.set(.string("Carts and receipts"), for: "description")
        let freshSaved = await fresh.save()
        XCTAssertTrue(freshSaved)
        XCTAssertEqual(source.creates, [
            BucketCreate(
                ecosystemId: "org.acme.shop", name: "Orders",
                metadata: BucketMetadata(description: "Carts and receipts")
            )
        ])
    }

    func testBucketLevelHasSettingsAndTables() async throws {
        let level = try await makeRail(FakeBucketsDataSource(buckets: [.fixture()])).level(["b-profile"])
        XCTAssertEqual(level.id, "bucket:b-profile")
        XCTAssertEqual(level.title, "Profile Basics")
        XCTAssertEqual(level.items.map(\.id), ["settings", "tables"])
        XCTAssertEqual(level.items.map(\.leadsTo), [.detail, .list])
    }

    func testUnknownBucketIsEmpty() async throws {
        guard case .empty = try await makeRail(FakeBucketsDataSource(buckets: [])).child(["nope"]) else {
            return XCTFail("expected empty")
        }
    }

    func testSettingsFormSavesNameAndDescription() async throws {
        let source = FakeBucketsDataSource(buckets: [.fixture()])
        let (detail, form) = try await makeRail(source).form(["b-profile", "settings"])
        XCTAssertEqual(detail.id, "bucket:b-profile:settings")
        XCTAssertEqual(detail.title, "Bucket")
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["name", "description"])
        XCTAssertEqual(form.state.value(for: "name"), .string("Profile Basics"))
        XCTAssertEqual(form.state.value(for: "description"), .string("Names and avatars"))
        form.state.set(.string("Profile"), for: "name")
        let saved = await form.state.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(source.updates.count, 1)
        XCTAssertEqual(source.updates[0].id, "b-profile")
        XCTAssertEqual(
            source.updates[0].input,
            BucketUpdate(name: "Profile", metadata: BucketMetadata(description: "Names and avatars"))
        )
    }

    func testBuiltInBucketHasNoDeleteAndCustomDeletes() async throws {
        let source = FakeBucketsDataSource(
            buckets: [.fixture(), .fixture(id: "b-sys", name: "System", kind: "system")]
        )
        let rail = makeRail(source)
        let (_, builtIn) = try await rail.form(["b-sys", "settings"])
        XCTAssertNil(builtIn.state.spec.actions.delete)
        let (_, custom) = try await rail.form(["b-profile", "settings"])
        let delete = try XCTUnwrap(custom.state.spec.actions.delete)
        XCTAssertEqual(delete.title, "Delete bucket")
        XCTAssertEqual(
            delete.confirmationText,
            "Delete bucket \"Profile Basics\"? Applications that granted it will lose those tables."
        )
        try await delete.perform()
        XCTAssertEqual(source.deletes, ["b-profile"])
    }

    func testTablesLevelListsTables() async throws {
        let source = FakeBucketsDataSource(
            buckets: [.fixture()],
            tables: [BucketTable(id: "t1", bucketId: "b-profile", sqlTableName: "contacts", name: "Contacts")]
        )
        let level = try await makeRail(source).level(["b-profile", "tables"])
        XCTAssertEqual(level.id, "bucket-tables:b-profile")
        XCTAssertEqual(level.title, "Tables")
        XCTAssertEqual(level.items.map(\.label), ["Contacts"])
        XCTAssertEqual(level.items.map(\.sublabel), ["contacts"])
        XCTAssertEqual(level.items.map(\.leadsTo), [.detail])
        XCTAssertEqual(level.emptyMessage, "No tables yet.")
        XCTAssertEqual(level.createAction?.title, "New table")
    }

    func testNewTableFormDerivesSQLNameAndRejectsDuplicates() async throws {
        let source = FakeBucketsDataSource(
            buckets: [.fixture()],
            tables: [BucketTable(id: "t1", bucketId: "b-profile", sqlTableName: "contacts", name: "Contacts")]
        )
        let spec = BucketsTopic(dataSource: source).createTableSpec(for: .fixture(), bucket: .fixture())
        XCTAssertEqual(spec.fields.map(\.key), ["name"])

        let blank = FormState(spec: spec)
        blank.set(.string("   "), for: "name")
        let blankSaved = await blank.save()
        XCTAssertFalse(blankSaved)
        XCTAssertEqual(blank.saveError, "Every table needs a name.")

        let duplicate = FormState(spec: spec)
        duplicate.set(.string("contacts"), for: "name")
        let duplicateSaved = await duplicate.save()
        XCTAssertFalse(duplicateSaved)
        XCTAssertEqual(duplicate.saveError, "Two tables share the name \"contacts\". Names must be unique.")

        let fresh = FormState(spec: spec)
        fresh.set(.string("Contact Notes"), for: "name")
        let freshSaved = await fresh.save()
        XCTAssertTrue(freshSaved)
        XCTAssertEqual(source.tableCreates, [
            BucketTableCreate(
                ecosystemId: "org.acme.shop", bucketId: "b-profile",
                sqlTableName: "contact_notes", name: "Contact Notes"
            )
        ])
    }

    func testTableDetailRenamesAndRemoves() async throws {
        let source = FakeBucketsDataSource(
            buckets: [.fixture()],
            tables: [BucketTable(id: "t1", bucketId: "b-profile", sqlTableName: "contacts", name: "Contacts")]
        )
        let (detail, form) = try await makeRail(source).form(["b-profile", "tables", "t1"])
        XCTAssertEqual(detail.id, "bucket-table:t1")
        XCTAssertEqual(detail.title, "Contacts")
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["name", "sqlTableName"])
        XCTAssertFalse(form.state.spec.fields[1].isEditable)
        form.state.set(.string("People"), for: "name")
        let saved = await form.state.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(source.tableUpdates.map(\.id), ["t1"])
        XCTAssertEqual(source.tableUpdates[0].input, BucketTableUpdate(name: "People"))
        let delete = try XCTUnwrap(form.state.spec.actions.delete)
        XCTAssertEqual(delete.title, "Remove table")
        XCTAssertEqual(
            delete.confirmationText, "Remove table \"Contacts\"? Data in it is not deleted until the bucket is."
        )
        try await delete.perform()
        XCTAssertEqual(source.tableDeletes, ["t1"])
    }

    func testFailuresSurfaceAsHubError() async throws {
        let source = FakeBucketsDataSource(buckets: [.fixture()])
        source.failure = .offline
        do {
            _ = try await makeRail(source).child([])
            XCTFail("expected throw")
        } catch let error as HubError {
            XCTAssertEqual(error, .offline)
        }
    }
}
