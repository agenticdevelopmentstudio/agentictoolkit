import Foundation

/// Who claims a stretch of work in a given repo and branch.
///
/// Only the claim. The rate is `BillingRate.rateCents`, resolved by the rollup
/// per segment, and whether billing is on is decided by the store's rollup
/// candidates; a copy of either here was computed and never read, and the
/// enabled flag already disagreed with the store for a repo whose project was
/// deleted.
public struct BillingRateResolution: Sendable, Equatable {
    public let repoId: String?
    /// nil is the Unassigned bucket.
    public let projectId: String?

    public init(repoId: String?, projectId: String?) {
        self.repoId = repoId
        self.projectId = projectId
    }
}

/// The rate-resolution ladder. Most specific wins; the first non-null rate is
/// taken:
///
/// 1. the repo row matching (`project_root`, `branch`)
/// 2. the repo row matching (`project_root`, `''`)
/// 3. the project's default rate
/// 4. the global default rate from settings
public enum BillingRate {

    public static func resolve(
        projectRoot: String,
        branch: String,
        repos: [BillingRepoDTO],
        projects: [BillingProjectDTO]
    ) -> BillingRateResolution {
        let forRoot = repos.filter { $0.projectRoot == projectRoot }
        // An exact branch match first, then the any-branch row for the repo.
        // The matched row decides the project; the rate walks the ladder
        // separately (see `rateCents`).
        let repo = forRoot.first { !$0.branch.isEmpty && $0.branch == branch }
            ?? forRoot.first { $0.branch.isEmpty }

        guard let repo else {
            // Unassigned: nobody claims this repo. The time is still tracked —
            // a forgotten setup step must not silently cost billable hours.
            return BillingRateResolution(repoId: nil, projectId: nil)
        }

        // A repo pointing at a deleted project claims the work for nobody.
        let project = projects.first { $0.id == repo.projectId }
        return BillingRateResolution(repoId: repo.id, projectId: project?.id)
    }

    /// The rate half of the ladder, for a segment that already knows its repo
    /// row (or has none — a hand-assigned or manual segment). Shared by
    /// `resolve` and the rollup so the two can never disagree on a rate:
    ///
    /// `branchRow?.rateCents ?? anyBranchRow?.rateCents ?? project default ?? global`
    ///
    /// A branch row with no rate of its own falls to the repo's any-branch row
    /// *before* the project default — step 2 of the ladder. Skipping it billed
    /// a feature branch at the project rate while the repo named its own.
    public static func rateCents(
        repo: BillingRepoDTO?,
        repos: [BillingRepoDTO],
        project: BillingProjectDTO?,
        globalDefaultRateCents: Int
    ) -> Int {
        if let rate = repo?.rateCents { return rate }
        if let repo, !repo.branch.isEmpty,
           let rate = repos.first(where: { $0.projectRoot == repo.projectRoot && $0.branch.isEmpty })?.rateCents {
            return rate
        }
        return project?.defaultRateCents ?? globalDefaultRateCents
    }
}
