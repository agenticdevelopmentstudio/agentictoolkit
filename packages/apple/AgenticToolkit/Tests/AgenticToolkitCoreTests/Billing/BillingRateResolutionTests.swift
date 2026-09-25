import XCTest
@testable import AgenticToolkitCore

/// The claim (`BillingRate.resolve`) and the rate ladder (`BillingRate.rateCents`)
/// together — what the rollup does for a segment derived in `root`/`branch`.
/// Whether billing is on is not decided here at all: `billingRollupCandidates`
/// decides it in SQL (see `BillingRollupTests`).
final class BillingRateResolutionTests: XCTestCase {

    private let projects = [
        BillingProjectDTO(id: "p1", name: "Alpha", defaultRateCents: 10_000),
        BillingProjectDTO(id: "p2", name: "Beta"),
        BillingProjectDTO(id: "p3", name: "Paused", billingEnabled: false)
    ]

    private func resolve(root: String, branch: String, repos: [BillingRepoDTO]) -> BillingRateResolution {
        BillingRate.resolve(projectRoot: root, branch: branch, repos: repos, projects: projects)
    }

    /// The rate the rollup would bill this work at.
    private func rate(
        root: String, branch: String, repos: [BillingRepoDTO], globalDefault: Int = 5_000
    ) -> Int {
        let resolution = resolve(root: root, branch: branch, repos: repos)
        return BillingRate.rateCents(
            repo: repos.first { $0.id == resolution.repoId },
            repos: repos,
            project: projects.first { $0.id == resolution.projectId },
            globalDefaultRateCents: globalDefault
        )
    }

    /// Most specific wins: an exact (root, branch) row beats the any-branch row
    /// for the same repo.
    func testBranchSpecificRateBeatsRepoWideRate() {
        let repos = [
            BillingRepoDTO(id: "r1", projectId: "p1", projectRoot: "/app", branch: "", rateCents: 9_000),
            BillingRepoDTO(id: "r2", projectId: "p1", projectRoot: "/app", branch: "rush", rateCents: 20_000)
        ]
        XCTAssertEqual(rate(root: "/app", branch: "rush", repos: repos), 20_000)
        XCTAssertEqual(resolve(root: "/app", branch: "rush", repos: repos).repoId, "r2")
        XCTAssertEqual(rate(root: "/app", branch: "main", repos: repos), 9_000)
    }

    /// A repo row with a null rate inherits the project default, not the global.
    func testNullRepoRateInheritsTheProjectDefault() {
        let repos = [BillingRepoDTO(id: "r1", projectId: "p1", projectRoot: "/app")]
        XCTAssertEqual(rate(root: "/app", branch: "main", repos: repos), 10_000)
    }

    /// A project with no default falls through to the global setting.
    func testNullProjectDefaultFallsThroughToGlobal() {
        let repos = [BillingRepoDTO(id: "r1", projectId: "p2", projectRoot: "/app")]
        XCTAssertEqual(rate(root: "/app", branch: "main", repos: repos), 5_000)
    }

    /// An unmapped repo is Unassigned: no project, no repo row.
    func testUnmappedRepoResolvesToUnassigned() {
        let resolution = resolve(root: "/elsewhere", branch: "main", repos: [])
        XCTAssertNil(resolution.projectId, "Unassigned")
        XCTAssertNil(resolution.repoId)
    }

    /// Disabled at repo level still attributes the work to the project — the
    /// time is tracked; only the rollup declines to bill it.
    func testARepoWithBillingOffStillClaimsTheWork() {
        let repos = [
            BillingRepoDTO(id: "r1", projectId: "p1", projectRoot: "/app", rateCents: 9_000,
                           billingEnabled: false)
        ]
        let resolution = resolve(root: "/app", branch: "main", repos: repos)
        XCTAssertEqual(resolution.projectId, "p1", "still attributed to the project")
        XCTAssertEqual(resolution.repoId, "r1")
    }

    /// A zero rate is a real rate — it bills $0, it does not mean "unset".
    func testZeroRateIsARateNotAnAbsence() {
        let repos = [BillingRepoDTO(id: "r1", projectId: "p1", projectRoot: "/app", rateCents: 0)]
        XCTAssertEqual(rate(root: "/app", branch: "main", repos: repos), 0)
    }

    /// A repo row pointing at a project that no longer exists must not crash or
    /// silently inherit someone else's rate — and claims the work for nobody.
    func testRepoWithAMissingProjectFallsBackToGlobal() {
        let repos = [BillingRepoDTO(id: "r1", projectId: "gone", projectRoot: "/app")]
        XCTAssertEqual(rate(root: "/app", branch: "main", repos: repos), 5_000)
        XCTAssertNil(resolve(root: "/app", branch: "main", repos: repos).projectId)
    }

    /// The ladder's second step: a branch row with no rate of its own takes
    /// the repo's any-branch rate before the project default.
    func testARatelessBranchRowInheritsTheAnyBranchRate() {
        let repos = [
            BillingRepoDTO(id: "r1", projectId: "p1", projectRoot: "/app", branch: "", rateCents: 9_000),
            BillingRepoDTO(id: "r2", projectId: "p1", projectRoot: "/app", branch: "rush")
        ]
        XCTAssertEqual(resolve(root: "/app", branch: "rush", repos: repos).repoId, "r2",
                       "the branch row still claims the work")
        XCTAssertEqual(rate(root: "/app", branch: "rush", repos: repos), 9_000,
                       "any-branch rate, not the project's 10_000")
    }
}
