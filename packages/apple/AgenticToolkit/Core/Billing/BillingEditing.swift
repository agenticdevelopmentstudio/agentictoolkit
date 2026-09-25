import Foundation

// The DTOs are immutable by design, so an edit is a copy with some fields
// changed. A parameter left nil keeps the field; a nullable field takes a
// double optional so `.some(nil)` can clear it. `createdAt`/`updatedAt` are
// the daemon's to stamp and are never offered here.

extension BillingClientDTO {
    public func replacing(
        id: String? = nil, name: String? = nil, contactName: String? = nil,
        email: String? = nil, phone: String? = nil, url: String? = nil,
        notes: String? = nil, currency: String? = nil, archived: Bool? = nil
    ) -> BillingClientDTO {
        BillingClientDTO(
            id: id ?? self.id, name: name ?? self.name,
            contactName: contactName ?? self.contactName, email: email ?? self.email,
            phone: phone ?? self.phone, url: url ?? self.url, notes: notes ?? self.notes,
            currency: currency ?? self.currency, archived: archived ?? self.archived,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

extension BillingProjectDTO {
    public func replacing(
        id: String? = nil, clientId: String?? = nil, name: String? = nil,
        notes: String? = nil, defaultRateCents: Int?? = nil,
        roundingMinutes: Int? = nil, roundingMode: String? = nil,
        billingEnabled: Bool? = nil, archived: Bool? = nil
    ) -> BillingProjectDTO {
        BillingProjectDTO(
            id: id ?? self.id, clientId: clientId ?? self.clientId, name: name ?? self.name,
            notes: notes ?? self.notes, defaultRateCents: defaultRateCents ?? self.defaultRateCents,
            roundingMinutes: roundingMinutes ?? self.roundingMinutes,
            roundingMode: roundingMode ?? self.roundingMode,
            billingEnabled: billingEnabled ?? self.billingEnabled,
            archived: archived ?? self.archived,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

extension BillingRepoDTO {
    public func replacing(
        projectRoot: String? = nil, branch: String? = nil,
        rateCents: Int?? = nil, billingEnabled: Bool? = nil
    ) -> BillingRepoDTO {
        BillingRepoDTO(
            id: id, projectId: projectId, projectRoot: projectRoot ?? self.projectRoot,
            branch: branch ?? self.branch, rateCents: rateCents ?? self.rateCents,
            billingEnabled: billingEnabled ?? self.billingEnabled,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

extension BillingEntryDTO {
    public func replacing(
        day: String? = nil, startedAt: String? = nil, endedAt: String? = nil,
        billedSeconds: Int? = nil, rateCents: Int? = nil, amountCents: Int? = nil,
        description: String? = nil
    ) -> BillingEntryDTO {
        BillingEntryDTO(
            id: id, projectId: projectId, clientId: clientId, day: day ?? self.day,
            groupKey: groupKey, startedAt: startedAt ?? self.startedAt,
            endedAt: endedAt ?? self.endedAt, rawSeconds: rawSeconds,
            billedSeconds: billedSeconds ?? self.billedSeconds,
            rateCents: rateCents ?? self.rateCents, currency: currency,
            amountCents: amountCents ?? self.amountCents,
            roundingMinutes: roundingMinutes, roundingMode: roundingMode, status: status,
            description: description ?? self.description, origin: origin, locked: locked,
            supplementsEntryId: supplementsEntryId, createdAt: createdAt, updatedAt: updatedAt
        )
    }

    /// Hours or rate edited by hand: the amount follows, through the same
    /// arithmetic the rollup uses, so the two can never disagree.
    public func repriced(billedSeconds: Int, rateCents: Int) -> BillingEntryDTO {
        replacing(
            billedSeconds: billedSeconds, rateCents: rateCents,
            amountCents: Money.amountCents(seconds: billedSeconds, rateCents: rateCents)
        )
    }
}

extension MoneyFormatter {
    /// A typed hourly rate in cents, or nil if it isn't a number or is outside
    /// what the daemon bills (`BillingLimits.defaultRateCents`). Every rate
    /// field takes its text through here, so they all refuse the same input.
    public func billingRate(parsing text: String) -> Int? {
        guard let cents = cents(parsing: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              BillingLimits.defaultRateCents.contains(cents) else { return nil }
        return cents
    }
}

/// A sidebar row with no text cannot be clicked, so a blank name shows as
/// "Untitled" until it is named.
public enum BillingRecordTitle {
    public static func of(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// What each of `projects` is called in a chooser, by id. A name two of
    /// them share is followed by its client's name, and by the start of its
    /// id if that still repeats, so no two items in one menu read alike and
    /// time can't be filed under a namesake of the project meant.
    public static func projectLabels(
        _ projects: [BillingProjectDTO], clients: [BillingClientDTO]
    ) -> [String: String] {
        let clientNames = Dictionary(
            clients.map { ($0.id, BillingRecordTitle.of($0.name)) }, uniquingKeysWith: { first, _ in first }
        )
        func distinguish(_ labels: [String: String], by suffix: (BillingProjectDTO) -> String) -> [String: String] {
            let counts = Dictionary(grouping: labels.values, by: { $0 }).mapValues(\.count)
            var result = labels
            for project in projects where counts[labels[project.id] ?? "", default: 0] > 1 {
                result[project.id] = "\(labels[project.id] ?? BillingRecordTitle.of(project.name)) — \(suffix(project))"
            }
            return result
        }
        let titles = Dictionary(
            projects.map { ($0.id, BillingRecordTitle.of($0.name)) }, uniquingKeysWith: { first, _ in first }
        )
        let withClients = distinguish(titles) { project in
            project.clientId.flatMap { clientNames[$0] } ?? "No Client"
        }
        return distinguish(withClients) { String($0.id.prefix(6)) }
    }
}
