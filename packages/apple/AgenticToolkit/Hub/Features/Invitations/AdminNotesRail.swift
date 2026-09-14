import AgenticToolkitHTDV
import Foundation

/// The "Admin notes" sub-rail shared by requests, pending users and invites.
/// Notes are stored as one list per subject row; every edit re-PUTs the whole list.
@MainActor
public struct AdminNotesRail {
    public static let item = HTDVItem(
        id: "notes", label: "Admin notes", sublabel: "Notes only your team can see.",
        systemImage: "note.text", leadsTo: .list
    )

    private let dataSource: any InvitationsDataSource
    private let ecosystemID: String
    private let subject: AdminNoteSubject
    private let subjectID: String

    public init(
        dataSource: any InvitationsDataSource, ecosystemID: String, subject: AdminNoteSubject, subjectID: String
    ) {
        self.dataSource = dataSource
        self.ecosystemID = ecosystemID
        self.subject = subject
        self.subjectID = subjectID
    }

    public static func historyText(_ entries: [HubHistoryEntry]) -> String {
        entries.isEmpty ? "No history." : entries.map(\.line).joined(separator: "\n")
    }

    public func child(path: [HTDVItem]) async throws -> HTDVChild {
        let notes: [HubAdminNote]
        do {
            notes = try await dataSource.notes(ecosystemID: ecosystemID, subject: subject, subjectID: subjectID)
        } catch { throw HubError.wrap(error) }
        guard let noteID = RailPath.id(at: 0, in: path) else {
            let items = notes.map {
                HTDVItem(
                    id: $0.id, label: $0.headline, sublabel: "\($0.createdBy) · \(HubDates.display($0.updatedAt))",
                    systemImage: "note.text", leadsTo: .detail
                )
            }
            let spec = createSpec()
            let action = HTDVCreateAction(title: "New note") { presenter in
                _ = await FormSheet.present(title: "New note", spec: spec, from: presenter)
            }
            return .level(
                HTDVLevel(
                    id: "admin-notes:\(subject.rawValue):\(subjectID)", title: "Admin notes", items: items,
                    emptyMessage: "No admin notes yet.", createAction: action
                )
            )
        }
        guard let note = notes.first(where: { $0.id == noteID }) else { return .empty }
        return .detail(noteDetail(note))
    }

    public func createSpec() -> FormSpec {
        let dataSource = self.dataSource
        let ecosystemID = self.ecosystemID
        let subject = self.subject
        let subjectID = self.subjectID
        let save = FormAction(id: "create", title: "Add") { values in
            let content = values["content"]?.stringValue ?? ""
            try await Self.rewrite(
                dataSource: dataSource, ecosystemID: ecosystemID, subject: subject, subjectID: subjectID
            ) { notes in notes + [AdminNoteInput(content: content)] }
        }
        return FormSpec(
            sections: [
                FormSection(fields: [
                    .textArea(FormTextAreaField(
                        key: "content", label: "Note", placeholder: "What the team should know", isRequired: true
                    ))
                ])
            ],
            actions: FormActions(save: save)
        )
    }

    private func noteDetail(_ note: HubAdminNote) -> HTDVDetail {
        let dataSource = self.dataSource
        let ecosystemID = self.ecosystemID
        let subject = self.subject
        let subjectID = self.subjectID
        let save = FormAction(id: "save", title: "Save") { values in
            let content = values["content"]?.stringValue ?? ""
            try await Self.rewrite(
                dataSource: dataSource, ecosystemID: ecosystemID, subject: subject, subjectID: subjectID
            ) { notes in
                notes.map { $0.id == note.id ? AdminNoteInput(id: note.id, content: content) : $0 }
            }
        }
        let delete = FormDeleteAction(title: "Delete note", confirmationText: "Delete this note?") {
            try await Self.rewrite(
                dataSource: dataSource, ecosystemID: ecosystemID, subject: subject, subjectID: subjectID
            ) { notes in notes.filter { $0.id != note.id } }
        }
        let spec = FormSpec(
            sections: [
                FormSection(fields: [
                    .textArea(FormTextAreaField(key: "content", label: "Note", isRequired: true)),
                    .readOnly(FormReadOnlyField(key: "author", label: "Author"))
                ])
            ],
            actions: FormActions(save: save, delete: delete)
        )
        return FormDetails.form(
            id: "admin-note:\(note.id)", title: "Note", spec: spec,
            values: ["content": .string(note.content), "author": .string(note.createdBy)]
        )
    }

    /// Fetch the current list, transform it, and PUT it back.
    ///
    /// `nonisolated` and `static`, taking every dependency as an explicit
    /// Sendable parameter, because `FormAction`/`FormDeleteAction.perform` are
    /// `@Sendable` but NOT `@MainActor`. `AdminNotesRail` is `@MainActor` and
    /// `public`, so it gets no implicit `Sendable` synthesis — capturing
    /// `self` in one of those closures (as the brief's own sample code does
    /// via `[self]`) is a Swift 6 concurrency error. Binding the Sendable
    /// pieces (`dataSource`, `ecosystemID`, `subject`, `subjectID`) as local
    /// lets before each closure, and routing the actual work through this
    /// `nonisolated static` function, avoids ever crossing back through
    /// `self`. Mirrors `CustomersTopic.input(from:ecosystemID:)`.
    nonisolated private static func rewrite(
        dataSource: any InvitationsDataSource, ecosystemID: String, subject: AdminNoteSubject, subjectID: String,
        _ transform: @Sendable ([AdminNoteInput]) -> [AdminNoteInput]
    ) async throws {
        do {
            let current = try await dataSource
                .notes(ecosystemID: ecosystemID, subject: subject, subjectID: subjectID)
                .map(\.input)
            try await dataSource.saveNotes(
                ecosystemID: ecosystemID, subject: subject, subjectID: subjectID, transform(current)
            )
        } catch { throw HubError.wrap(error) }
    }
}
