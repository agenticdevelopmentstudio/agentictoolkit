import Foundation
import AgenticToolkitSync

/// One queued call against adh's `/content/markdown` routes.
///
/// The intents map one-for-one onto `routes/markdownDocuments.ts`:
///
/// | intent | request |
/// |---|---|
/// | `create` | `POST /` with `{ content, category?, tags?, note?, doc? }` |
/// | `update` | `PUT /:id` with `{ content?, category?, tags? }` |
/// | `delete` | `DELETE /:id` |
/// | `publish` | `POST /:id/publish` with `{ route }` |
/// | `unpublish` | `POST /:id/unpublish` |
/// | `finalize` | `POST /:id/finalize` |
/// | `definalize` | `POST /:id/definalize` |
///
/// Reads are absent on purpose: the sync pull supplies everything except
/// version history, which has no local table at all (`content.markdown_versions`
/// carries no sync columns, so it is not in `ADHSyncCatalog`).
public enum MarkdownRemoteIntent: String, Sendable, CaseIterable {
    case create, update, delete, publish, unpublish, finalize, definalize
}

public struct MarkdownRemoteOp: Equatable, Sendable {
    public let opID: String
    public let documentID: String
    public let intent: MarkdownRemoteIntent
    public let payload: [String: JSONValue]
    public let createdAt: Date

    public init(
        opID: String, documentID: String, intent: MarkdownRemoteIntent,
        payload: [String: JSONValue], createdAt: Date
    ) {
        self.opID = opID
        self.documentID = documentID
        self.intent = intent
        self.payload = payload
        self.createdAt = createdAt
    }
}

/// Drains `_markdown_outbox` against adh.
///
/// Nothing implements this yet — Whippet holds no adh credentials — and that is
/// the whole reason the queue is durable rather than best-effort: edits made
/// before a writer exists must still be there when one does.
public protocol MarkdownRemoteWriter: Sendable {
    /// Throws to leave the op queued. Returning normally means adh accepted it.
    func send(_ remoteOp: MarkdownRemoteOp) async throws
}
