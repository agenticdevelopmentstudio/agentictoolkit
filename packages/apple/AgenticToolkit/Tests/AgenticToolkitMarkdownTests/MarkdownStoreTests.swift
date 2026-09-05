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

    @Test("an update queues content alone — the PUT body has no other key this store fills")
    func updatePayloadCarriesContentOnly() throws {
        let store = try store()
        var document = try store.createDocument(content: "first", markers: [])
        try store.completeRemoteOp(opID: try store.pendingRemoteOps(limit: 1)[0].opID)
        document.content = "second"
        try store.updateDocument(document)
        let queued = try store.pendingRemoteOps(limit: 10)
        #expect(queued.count == 1)
        #expect(queued[0].intent == .update)
        #expect(queued[0].payload == ["content": .string("second")])
    }

    @Test("moving visibility through an update is refused — publish is its own route")
    func updateRefusesVisibilityDrift() throws {
        let store = try store()
        var document = try store.createDocument(content: "first", markers: [])
        document.visibility = .public
        #expect(throws: MarkdownStoreError.useDedicatedIntent(
            field: "visibility",
            method: "publishDocument(id:route:) / unpublishDocument(id:)")) {
            try store.updateDocument(document)
        }
    }

    @Test("moving a public route through an update is refused")
    func updateRefusesRouteDrift() throws {
        let store = try store()
        var document = try store.createDocument(content: "first", markers: [])
        document.publicRoute = "/first"
        #expect(throws: MarkdownStoreError.useDedicatedIntent(
            field: "public_route",
            method: "publishDocument(id:route:) / unpublishDocument(id:)")) {
            try store.updateDocument(document)
        }
    }

    @Test("moving stage through an update is refused — finalize is its own route")
    func updateRefusesStageDrift() throws {
        let store = try store()
        var document = try store.createDocument(content: "first", markers: [])
        document.stage = .final
        #expect(throws: MarkdownStoreError.useDedicatedIntent(
            field: "stage", method: "finalizeDocument(id:) / definalizeDocument(id:)")) {
            try store.updateDocument(document)
        }
    }

    @Test("publish moves visibility and route together and queues the publish route")
    func publishSetsBothHalvesOfTheInvariant() throws {
        let store = try store()
        let created = try store.createDocument(content: "first", markers: [])
        try store.completeRemoteOp(opID: try store.pendingRemoteOps(limit: 1)[0].opID)
        try store.publishDocument(id: created.id, route: "/first")

        let loaded = try #require(try store.document(id: created.id))
        #expect(loaded.visibility == .public)
        #expect(loaded.publicRoute == "/first")
        let queued = try store.pendingRemoteOps(limit: 10)
        #expect(queued.count == 1)
        #expect(queued[0].intent == .publish)
        #expect(queued[0].payload == ["route": .string("/first")])
    }

    @Test("publishing with a blank route is refused rather than half-applied")
    func publishRefusesABlankRoute() throws {
        let store = try store()
        let created = try store.createDocument(content: "first", markers: [])
        #expect(throws: MarkdownStoreError.inconsistentPublicationState(id: created.id)) {
            try store.publishDocument(id: created.id, route: "   ")
        }
        let loaded = try #require(try store.document(id: created.id))
        #expect(loaded.visibility == .private)
        #expect(loaded.publicRoute == nil)
    }

    @Test("unpublish clears the route and goes private in one move")
    func unpublishClearsBothHalves() throws {
        let store = try store()
        let created = try store.createDocument(content: "first", markers: [])
        try store.publishDocument(id: created.id, route: "/first")
        try store.unpublishDocument(id: created.id)

        let loaded = try #require(try store.document(id: created.id))
        #expect(loaded.visibility == .private)
        #expect(loaded.publicRoute == nil)
        let intents = try store.pendingRemoteOps(limit: 10).map(\.intent)
        #expect(intents.contains(.unpublish))
    }

    @Test("finalize and definalize move stage and queue their own intents")
    func finalizeAndDefinalizeMoveStage() throws {
        let store = try store()
        let created = try store.createDocument(content: "first", markers: [])
        try store.completeRemoteOp(opID: try store.pendingRemoteOps(limit: 1)[0].opID)

        try store.finalizeDocument(id: created.id)
        #expect(try #require(try store.document(id: created.id)).stage == .final)
        #expect(try store.pendingRemoteOps(limit: 10).map(\.intent) == [.finalize])

        try store.definalizeDocument(id: created.id)
        #expect(try #require(try store.document(id: created.id)).stage == .draft)
        #expect(try store.pendingRemoteOps(limit: 10).map(\.intent) == [.finalize, .definalize])
    }

    @Test("a lifecycle call for a document that is not there says so")
    func lifecycleOfMissingDocumentThrows() throws {
        let store = try store()
        #expect(throws: MarkdownStoreError.notFound("ghost")) {
            try store.finalizeDocument(id: "ghost")
        }
        #expect(throws: MarkdownStoreError.notFound("ghost")) {
            try store.unpublishDocument(id: "ghost")
        }
    }

    @Test("a merge does not drop a key an earlier queued op already set")
    func mergePreservesEarlierPayloadKeys() throws {
        let store = try store()
        var document = try store.createDocument(content: "first", markers: [.note])
        // The `create` is still pending, so the update below coalesces into it
        // rather than into a fresh `update` row.
        document.content = "second"
        try store.updateDocument(document)

        let queued = try store.pendingRemoteOps(limit: 10)
        #expect(queued.count == 1)
        #expect(queued[0].intent == .create)
        #expect(queued[0].payload["note"] == .bool(true))   // set by the create
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

    @Test("an outbox row with an unreadable created_at throws rather than inventing a send time")
    func pendingRemoteOpsThrowsOnUnreadableTimestamp() throws {
        let store = try store()
        _ = try store.createDocument(content: "x", markers: [])
        let opID = try store.pendingRemoteOps(limit: 1)[0].opID
        try store.database.write { conn in
            try conn.execute(sql: "UPDATE _markdown_outbox SET created_at = 'not a date'")
        }
        #expect(throws: MarkdownStoreError.unreadableOutboxTimestamp(opID: opID)) {
            try store.pendingRemoteOps(limit: 10)
        }
    }

    /// Was "…is skipped". Skipping is a lie the user cannot see through: the
    /// note is simply absent from the list, nothing anywhere says why, and the
    /// conclusion available to them is that their work was lost. Throwing names
    /// the row and the column, and matches what `pendingRemoteOps` already does
    /// with exactly the same kind of corrupt value one test up.
    @Test("a document row with an unreadable timestamp throws, naming the row and column")
    func unreadableDocumentTimestampThrows() throws {
        let store = try store()
        _ = try store.createDocument(content: "good", markers: [.note])
        let bad = try store.createDocument(content: "bad", markers: [.note])
        try store.database.write { conn in
            try conn.execute(
                sql: "UPDATE markdown SET updated_at = 'garbage' WHERE id = ?", arguments: [bad.id])
        }
        #expect(throws: MarkdownStoreError.unreadableTimestamp(id: bad.id, column: "updated_at")) {
            try store.document(id: bad.id)
        }
        #expect(throws: MarkdownStoreError.unreadableTimestamp(id: bad.id, column: "updated_at")) {
            try store.documents(marker: .note)
        }
    }

    /// adh's columns are Postgres `timestamp` and its OpenAPI declares them as
    /// unformatted strings, so this is the shape a pulled row can genuinely
    /// arrive in — and `MarkdownProjection` stores verbatim whatever it cannot
    /// parse. Before the repair pass this row read as unparseable.
    @Test("a Postgres-shaped timestamp on disk is read, not rejected")
    func postgresTimestampIsReadable() throws {
        let store = try store()
        let doc = try store.createDocument(content: "x", markers: [.note])
        try store.database.write { conn in
            try conn.execute(
                sql: "UPDATE markdown SET updated_at = ? WHERE id = ?",
                arguments: ["2026-04-13 16:18:07.798+00", doc.id])
        }
        let loaded = try #require(try store.document(id: doc.id))
        #expect(MarkdownTimestamp.string(loaded.updatedAt) == "2026-04-13T16:18:07.798Z")
    }

    // MARK: - Frontmatter provenance

    @Test("owned frontmatter keys are written with the document and read back per document")
    func ownedFrontmatterKeysRoundTrip() throws {
        let store = try store()
        let mine = try store.createDocument(
            content: "---\ntitle: T\n---\nbody", markers: [.note],
            ownedFrontmatterKeys: ["title"])
        let theirs = try store.createDocument(content: "plain", markers: [.note])
        #expect(try store.ownedFrontmatterKeys(forDocument: mine.id) == ["title"])
        #expect(try store.ownedFrontmatterKeys(forDocument: theirs.id) == [])
        #expect(try store.ownedFrontmatterKeysByDocument() == [mine.id: ["title"]])
    }

    @Test("updating with a new set replaces it; updating without one leaves it alone")
    func ownedFrontmatterKeysReplaceOrPersist() throws {
        let store = try store()
        let doc = try store.createDocument(
            content: "x", markers: [.note], ownedFrontmatterKeys: ["title", "pinned"])
        try store.updateDocument(doc)
        #expect(try store.ownedFrontmatterKeys(forDocument: doc.id) == ["title", "pinned"])
        try store.updateDocument(doc, ownedFrontmatterKeys: ["pinned"])
        #expect(try store.ownedFrontmatterKeys(forDocument: doc.id) == ["pinned"])
        try store.updateDocument(doc, ownedFrontmatterKeys: [])
        #expect(try store.ownedFrontmatterKeys(forDocument: doc.id) == [])
    }

    @Test("deleting a document takes its ownership record with it")
    func deletingClearsOwnedFrontmatterKeys() throws {
        let store = try store()
        let doc = try store.createDocument(
            content: "x", markers: [.note], ownedFrontmatterKeys: ["title"])
        try store.deleteDocument(id: doc.id)
        #expect(try store.ownedFrontmatterKeys(forDocument: doc.id) == [])
    }

    @Test("deleting a document whose create never drained drops the pair instead of queueing a delete")
    func deleteCancelsAPendingCreate() throws {
        let store = try store()
        let created = try store.createDocument(content: "never sent", markers: [.note])
        try store.deleteDocument(id: created.id)
        #expect(try store.pendingRemoteOps(limit: 10).isEmpty)
    }

    @Test("deleting a document adh already has queues a delete and nothing else")
    func deleteQueuesADeleteOnceTheCreateHasDrained() throws {
        let store = try store()
        let created = try store.createDocument(content: "sent", markers: [.note])
        try store.completeRemoteOp(opID: try store.pendingRemoteOps(limit: 1)[0].opID)
        try store.publishDocument(id: created.id, route: "/sent")
        try store.deleteDocument(id: created.id)

        let queued = try store.pendingRemoteOps(limit: 10)
        #expect(queued.map(\.intent) == [.delete])   // the pending publish is moot and was dropped
    }

    @Test("the queue comes back in enqueue order even when every op shares a timestamp")
    func queueIsOrderedBySequenceNotTimestamp() throws {
        let store = try store()
        // One `now` for all three writes: `created_at` is truncated to
        // milliseconds, so ordering on it would tie and fall back to the
        // random UUIDv7 tie-break.
        let now = Date()
        let first = try store.createDocument(content: "first", markers: [], now: now)
        try store.completeRemoteOp(opID: try store.pendingRemoteOps(limit: 1)[0].opID)
        try store.finalizeDocument(id: first.id, now: now)
        try store.definalizeDocument(id: first.id, now: now)
        try store.publishDocument(id: first.id, route: "/first", now: now)

        let queued = try store.pendingRemoteOps(limit: 10)
        #expect(queued.map(\.intent) == [.finalize, .definalize, .publish])
        #expect(Set(queued.map(\.createdAt)).count == 1)
    }

    @Test("a create's response id is recorded and reaches every later op for the document")
    func drainAdoptsTheServerMintedID() async throws {
        let store = try store()
        var document = try store.createDocument(content: "one", markers: [])
        let writer = RecordingWriter(minting: "adh-42")
        try await store.drainRemoteQueue(into: writer, limit: 10)
        #expect(try store.remoteID(forDocument: document.id) == "adh-42")

        document.content = "two"
        try store.updateDocument(document)
        try await store.drainRemoteQueue(into: writer, limit: 10)
        #expect(await writer.sentIntents == [.create, .update])
        // The create had no remote id yet; the update addresses `/adh-42`.
        #expect(await writer.sentRemoteIDs == [nil, "adh-42"])
    }

    @Test("a writer that reports no id leaves the document without one")
    func drainToleratesAWriterThatMintsNothing() async throws {
        let store = try store()
        let created = try store.createDocument(content: "one", markers: [])
        try await store.drainRemoteQueue(into: RecordingWriter(), limit: 10)
        #expect(try store.remoteID(forDocument: created.id) == nil)
    }

    @Test("defaultPath puts the database beside Whippet's, not inside it")
    func defaultPathIsItsOwnFile() {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(MarkdownStore.defaultPath(inHome: home) == "/Users/example/.whippet/Markdown.db")
    }
}

/// Records what it was handed, and answers a `create` with the id adh would
/// have minted — which is what lets a test observe the reconciliation.
private actor RecordingWriter: MarkdownRemoteWriter {
    private(set) var sentIntents: [MarkdownRemoteIntent] = []
    private(set) var sentRemoteIDs: [String?] = []
    private let mintedID: String?

    init(minting mintedID: String? = nil) { self.mintedID = mintedID }

    func send(_ remoteOp: MarkdownRemoteOp) async throws -> String? {
        sentIntents.append(remoteOp.intent)
        sentRemoteIDs.append(remoteOp.remoteID)
        return remoteOp.intent == .create ? mintedID : nil
    }
}

private struct FailingWriter: MarkdownRemoteWriter {
    struct Offline: Error {}
    func send(_ remoteOp: MarkdownRemoteOp) async throws -> String? { throw Offline() }
}
