import Testing
import Foundation
import GRDB
import AgenticToolkitSync
@testable import AgenticToolkitMarkdown

@Suite("MarkdownStore")
struct MarkdownStoreTests {

    private func store() throws -> MarkdownStore {
        try MarkdownStore(path: ":memory:", customerID: "cust-1", ecosystemID: "eco-1")
    }

    @Test("a created document round-trips with its derived fields")
    func createRoundTrips() throws {
        let store = try store()
        let created = try store.createDocument(content: "# Hello\n\nBody text.", markers: [.note])
        let loaded = try #require(try store.document(id: created.id))
        #expect(loaded.content == "# Hello\n\nBody text.")
        #expect(loaded.title == "Hello")
        #expect(loaded.currentVersion == 1)
        #expect(loaded.visibility == .private)
        #expect(loaded.stage == .draft)
        #expect(loaded.isDeleted == false)
    }

    @Test("the derived columns are written as a cache of the content")
    func derivedColumnsAreWritten() throws {
        let store = try store()
        let created = try store.createDocument(content: "# Hello\n\nBody.", markers: [])
        try store.database.read { conn in
            let row = try #require(try Row.fetchOne(
                conn, sql: "SELECT title, content_hash, size_bytes FROM markdown WHERE id = ?",
                arguments: [created.id]))
            #expect(row["title"] as String == "Hello")
            #expect(row["content_hash"] as String == MarkdownText.contentHash("# Hello\n\nBody."))
            #expect(row["size_bytes"] as Int == MarkdownText.byteLength("# Hello\n\nBody."))
        }
    }

    @Test("a document id is a lowercase UUID string")
    func idIsLowercased() throws {
        let store = try store()
        let created = try store.createDocument(content: "x", markers: [])
        #expect(created.id == created.id.lowercased())
        #expect(UUID(uuidString: created.id) != nil)
    }

    @Test("markers are what `documents(marker:)` lists on")
    func markersFilterListing() throws {
        let store = try store()
        let note = try store.createDocument(content: "a note", markers: [.note])
        _ = try store.createDocument(content: "a doc", markers: [.doc])
        #expect(try store.documents(marker: .note).map(\.id) == [note.id])
        #expect(try store.documents(marker: .paper).isEmpty)
    }

    @Test("a marker row carries the store's customer id")
    func markersInheritCustomer() throws {
        let store = try store()
        let created = try store.createDocument(content: "a paper", markers: [.paper])
        try store.database.read { conn in
            let customer = try String.fetchOne(
                conn, sql: "SELECT customer_id FROM papers WHERE markdown_id = ?",
                arguments: [created.id])
            #expect(customer == "cust-1")   // adh's inherit_customer trigger, done explicitly
        }
    }

    @Test("an update recomputes the derived columns and bumps updated_at")
    func updateRecomputesDerived() throws {
        let store = try store()
        var document = try store.createDocument(content: "# Old", markers: [.note])
        let originalUpdate = document.updatedAt
        document.content = "# New\n\nMore."
        try store.updateDocument(document)
        let loaded = try #require(try store.document(id: document.id))
        #expect(loaded.title == "New")
        #expect(loaded.updatedAt >= originalUpdate)
    }

    @Test("a delete tombstones both flags and hides the document")
    func deleteSetsBothFlags() throws {
        let store = try store()
        let created = try store.createDocument(content: "gone", markers: [.note])
        try store.deleteDocument(id: created.id)
        #expect(try store.document(id: created.id) == nil)
        #expect(try store.documents(marker: .note).isEmpty)
        try store.database.read { conn in
            let row = try #require(try Row.fetchOne(
                conn, sql: "SELECT is_deleted, deleted_at FROM markdown WHERE id = ?",
                arguments: [created.id]))
            #expect(row["is_deleted"] as Int == 1)
            #expect(row["deleted_at"] as String? != nil)
        }
        // The marker is tombstoned too, so the document can be re-marked later.
        try store.database.read { conn in
            let deletedAt = try String.fetchOne(
                conn, sql: "SELECT deleted_at FROM notes WHERE markdown_id = ?",
                arguments: [created.id])
            #expect(deletedAt != nil)
        }
    }

    @Test("updating a document that is not there says so")
    func updateOfMissingDocumentThrows() throws {
        let store = try store()
        let ghost = MarkdownDocument.new(id: "00000000-0000-0000-0000-000000000000",
                                         content: "x", ownerKind: .customer, ownerID: "")
        #expect(throws: MarkdownStoreError.notFound("00000000-0000-0000-0000-000000000000")) {
            try store.updateDocument(ghost)
        }
    }

    @Test("staging a document through the sync outbox is refused, as adh intends")
    func documentsArePullOnly() async throws {
        let store = try store()
        await #expect(throws: SyncStoreFailure.pullOnlyResource("content.markdown")) {
            try await store.syncStore.stage(LocalMutation(
                resource: "content.markdown", rowId: "m1", type: .upsert, data: [:]))
        }
    }

    @Test("every write queues a REST intent")
    func writesQueueIntents() throws {
        let store = try store()
        let created = try store.createDocument(content: "hello", markers: [.note])
        let queued = try store.pendingRemoteOps(limit: 10)
        #expect(queued.count == 1)
        #expect(queued[0].intent == .create)
        #expect(queued[0].documentID == created.id)
        #expect(queued[0].payload["content"] == .string("hello"))
        #expect(queued[0].payload["note"] == .bool(true))
    }

    @Test("title is never sent — adh derives it and rejects a caller's")
    func titleIsNeverQueued() throws {
        let store = try store()
        _ = try store.createDocument(content: "# Titled", markers: [])
        #expect(try store.pendingRemoteOps(limit: 10)[0].payload["title"] == nil)
    }

    @Test("an update queues visibility, stage and route alongside content")
    func updatePayloadCarriesAuthoredFields() throws {
        let store = try store()
        var document = try store.createDocument(content: "first", markers: [])
        try store.completeRemoteOp(opID: try store.pendingRemoteOps(limit: 1)[0].opID)
        document.visibility = .public
        try store.updateDocument(document)
        let queued = try store.pendingRemoteOps(limit: 10)
        #expect(queued.count == 1)
        #expect(queued[0].payload["content"] == .string("first"))
        #expect(queued[0].payload["visibility"] == .string("public"))
        #expect(queued[0].payload["stage"] == .string("draft"))
        #expect(queued[0].payload["public_route"] == .null)
    }

    @Test("clearing a public route queues an explicit null, not an omitted key")
    func clearingRouteQueuesExplicitNull() throws {
        let store = try store()
        var document = try store.createDocument(content: "first", markers: [])
        document.publicRoute = "/first"
        try store.updateDocument(document)
        try store.completeRemoteOp(opID: try store.pendingRemoteOps(limit: 1)[0].opID)

        document.publicRoute = nil
        try store.updateDocument(document)
        let queued = try store.pendingRemoteOps(limit: 10)
        #expect(queued.count == 1)
        #expect(queued[0].payload["public_route"] == .null)
        #expect(queued[0].payload.keys.contains("public_route"))
    }

    @Test("a merge does not drop a field an earlier queued update already set")
    func mergePreservesEarlierAuthoredFields() throws {
        let store = try store()
        var document = try store.createDocument(content: "first", markers: [])
        // The `create` is still pending, so both updates below coalesce into it
        // rather than into a fresh `update` row — this exercises the same
        // field-wise merge branch either way.
        document.visibility = .public
        try store.updateDocument(document)
        document.content = "second"
        try store.updateDocument(document)

        let queued = try store.pendingRemoteOps(limit: 10)
        #expect(queued.count == 1)
        #expect(queued[0].intent == .create)
        #expect(queued[0].payload["visibility"] == .string("public"))
        #expect(queued[0].payload["content"] == .string("second"))
    }

    @Test("an outbox row with an unreadable intent throws rather than defaulting to update")
    func pendingRemoteOpsThrowsOnUnknownIntent() throws {
        let store = try store()
        _ = try store.createDocument(content: "x", markers: [])
        try store.database.write { conn in
            try conn.execute(sql: "UPDATE _markdown_outbox SET intent = 'bogus'")
        }
        #expect(throws: MarkdownStoreError.unknownRemoteIntent("bogus")) {
            try store.pendingRemoteOps(limit: 10)
        }
    }

    @Test("an outbox row with a corrupt payload throws rather than reading as empty")
    func pendingRemoteOpsThrowsOnCorruptPayload() throws {
        let store = try store()
        _ = try store.createDocument(content: "x", markers: [])
        try store.database.write { conn in
            try conn.execute(sql: "UPDATE _markdown_outbox SET payload = 'not json'")
        }
        #expect(throws: (any Error).self) {
            try store.pendingRemoteOps(limit: 10)
        }
    }

    @Test("an update that arrives while a create is pending merges into the create")
    func updateMergesIntoPendingCreate() throws {
        let store = try store()
        var document = try store.createDocument(content: "first", markers: [])
        document.content = "second"
        try store.updateDocument(document)
        let queued = try store.pendingRemoteOps(limit: 10)
        #expect(queued.count == 1)
        #expect(queued[0].intent == .create)          // still a create — the row is not on the server yet
        #expect(queued[0].payload["content"] == .string("second"))
    }

    @Test("two updates coalesce into one")
    func updatesCoalesce() throws {
        let store = try store()
        var document = try store.createDocument(content: "first", markers: [])
        try store.completeRemoteOp(opID: try store.pendingRemoteOps(limit: 1)[0].opID)
        document.content = "second"
        try store.updateDocument(document)
        document.content = "third"
        try store.updateDocument(document)
        let queued = try store.pendingRemoteOps(limit: 10)
        #expect(queued.count == 1)
        #expect(queued[0].intent == .update)
        #expect(queued[0].payload["content"] == .string("third"))
    }

    @Test("the queue survives a reopen")
    func queueIsDurable() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("Markdown.db").path

        let first = try MarkdownStore(path: path, customerID: "cust-1", ecosystemID: "eco-1")
        _ = try first.createDocument(content: "durable", markers: [.note])
        #expect(try first.pendingRemoteOps(limit: 10).count == 1)

        let second = try MarkdownStore(path: path, customerID: "cust-1", ecosystemID: "eco-1")
        #expect(try second.pendingRemoteOps(limit: 10).count == 1)
        #expect(try second.documents(marker: .note).count == 1)
    }

    @Test("draining hands each op to the writer and clears what it accepts")
    func drainClearsAcceptedOps() async throws {
        let store = try store()
        _ = try store.createDocument(content: "one", markers: [])
        let writer = RecordingWriter()
        try await store.drainRemoteQueue(into: writer, limit: 10)
        #expect(await writer.sentIntents == [.create])
        #expect(try store.pendingRemoteOps(limit: 10).isEmpty)
    }

    @Test("a writer that fails leaves the op queued")
    func drainKeepsRejectedOps() async throws {
        let store = try store()
        _ = try store.createDocument(content: "one", markers: [])
        await #expect(throws: (any Error).self) {
            try await store.drainRemoteQueue(into: FailingWriter(), limit: 10)
        }
        #expect(try store.pendingRemoteOps(limit: 10).count == 1)
    }

    @Test("defaultPath puts the database beside Whippet's, not inside it")
    func defaultPathIsItsOwnFile() {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(MarkdownStore.defaultPath(inHome: home) == "/Users/example/.whippet/Markdown.db")
    }
}

private actor RecordingWriter: MarkdownRemoteWriter {
    private(set) var sentIntents: [MarkdownRemoteIntent] = []
    func send(_ remoteOp: MarkdownRemoteOp) async throws { sentIntents.append(remoteOp.intent) }
}

private struct FailingWriter: MarkdownRemoteWriter {
    struct Offline: Error {}
    func send(_ remoteOp: MarkdownRemoteOp) async throws { throw Offline() }
}
