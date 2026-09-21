import Testing
import Foundation
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The one line under the results table, which is the only thing that tells a
/// reader whether the registry has more to give.
///
/// Four outcomes share one function and three of them are easy to mistake for
/// each other: nothing matched *this query*, the registry returned nothing at
/// all, here is the whole result set, and here is the front of a larger one.
/// The last is the one that matters — "50 extensions." and "Showing 50 of
/// 2,322." are the difference between a reader narrowing their search and a
/// reader concluding the extension they want is not published.
@MainActor
struct ExtensionsBrowsePanelSummaryTests {

    /// Decoded rather than constructed, because `OpenVSXSearchEntry`'s
    /// initialiser is the synthesised one and every field of it is irrelevant
    /// here — only how many there are.
    private func page(showing count: Int, of total: Int) throws -> OpenVSXSearchPage {
        let rows = (0..<count).map { index in
            """
            { "namespace": "acme", "name": "widget\(index)", "version": "1.0.0" }
            """
        }
        let json = """
        { "offset": 0, "totalSize": \(total), "extensions": [\(rows.joined(separator: ","))] }
        """
        return try JSONDecoder().decode(
            OpenVSXSearchPage.self, from: Data(json.utf8))
    }

    private func summary(showing count: Int, of total: Int, query: String) throws -> String {
        ExtensionsBrowsePanel.resultsSummary(
            for: try page(showing: count, of: total), query: query)
    }

    // MARK: - Nothing came back

    /// The query has to appear. "Nothing matched." over a table the user is
    /// still looking at reads as a statement about the registry; with the word
    /// in it, it reads as a statement about the word — which is the one the
    /// user can act on.
    @Test("nothing matching a query names the query")
    func nothingMatchingAQueryNamesTheQuery() throws {
        let line = try summary(showing: 0, of: 0, query: "vim")

        #expect(line.contains("vim"))
        #expect(line == "Nothing matched “vim”.")
    }

    /// The default listing, which runs with an empty field. There is no word
    /// to blame, so the sentence must not pretend there is — interpolating an
    /// empty query gives `Nothing matched “”.`
    @Test("an empty answer to no query blames the registry, not a word")
    func anEmptyAnswerToNoQueryBlamesTheRegistry() throws {
        let line = try summary(showing: 0, of: 0, query: "")

        #expect(line == "The registry returned nothing.")
        #expect(!line.contains("“"))
    }

    /// A registry that reports a total but hands back no rows — the shape a
    /// bad `offset` produces. Row count decides, not the total, or this reads
    /// "Showing 0 of 2,322" over an empty table.
    @Test("no rows is an empty answer however large the total claims to be")
    func noRowsIsEmptyHoweverLargeTheTotal() throws {
        let line = try summary(showing: 0, of: 2322, query: "vim")

        #expect(line == "Nothing matched “vim”.")
    }

    // MARK: - The whole result set

    @Test("a single result is singular")
    func aSingleResultIsSingular() throws {
        #expect(try summary(showing: 1, of: 1, query: "vim") == "1 extension.")
    }

    @Test("more than one result is plural")
    func moreThanOneResultIsPlural() throws {
        #expect(try summary(showing: 3, of: 3, query: "vim") == "3 extensions.")
    }

    /// A registry whose `totalSize` is smaller than the page it just sent.
    /// Nothing forbids it — the two numbers are counted at different moments
    /// on the server — and the subtraction a "and N more" phrasing would do
    /// here is negative. The `>=` is what keeps it out of the truncated
    /// branch.
    @Test("more rows than the claimed total is still just a count")
    func moreRowsThanTheClaimedTotalIsStillACount() throws {
        #expect(try summary(showing: 3, of: 1, query: "vim") == "3 extensions.")
    }

    // MARK: - The front of a larger set

    /// Both numbers, in the right order. Swapping them compiles, reads
    /// plausibly, and tells the user the registry has fewer extensions than it
    /// just sent them.
    @Test("a truncated page shows the page count first and the total second")
    func aTruncatedPageShowsBothNumbersInOrder() throws {
        let line = try summary(showing: 50, of: 2322, query: "vim")

        let shown = ExtensionsBrowsePanel.number(50)
        let total = ExtensionsBrowsePanel.number(2322)
        #expect(line == "Showing \(shown) of \(total). Narrow the search to see the rest.")
        let shownAt = try #require(line.range(of: shown))
        let totalAt = try #require(line.range(of: total))
        #expect(shownAt.lowerBound < totalAt.lowerBound)
    }

    /// And it has to say what to do about it. A count with no instruction
    /// leaves "is the rest reachable?" unanswered, and the answer — narrow the
    /// query — is not guessable from a list that has no paging control.
    @Test("a truncated page says how to see the rest")
    func aTruncatedPageSaysHowToSeeTheRest() throws {
        let line = try summary(showing: 50, of: 2322, query: "vim")

        #expect(line.contains("Narrow the search"))
    }

    /// One short of the total is still truncated. An off-by-one here shows up
    /// only on the page that is almost complete, which is the one nobody
    /// checks by hand.
    @Test("one row short of the total is still a truncated page")
    func oneRowShortIsStillTruncated() throws {
        let line = try summary(showing: 2, of: 3, query: "vim")

        #expect(line.hasPrefix("Showing "))
    }

    // MARK: - The number formatter

    /// Grouping is the whole point of running these through a formatter, and
    /// the separator is the reader's, not this test's — so what is asserted is
    /// that the digits survive it and that something was inserted between
    /// them. `2322` unseparated is what a `String(value)` fallback produces.
    @Test("a large number is grouped without losing a digit")
    func aLargeNumberIsGroupedWithoutLosingADigit() {
        let formatted = ExtensionsBrowsePanel.number(1_234_567)

        #expect(formatted.filter(\.isNumber) == "1234567")
        #expect(formatted.count > 7)
    }

    /// And a small one is not decorated. A formatter left on the wrong style
    /// turns 50 into "50.000" or "5,000%", which reads as a different number
    /// rather than as a broken one.
    @Test("a small number is left alone")
    func aSmallNumberIsLeftAlone() {
        #expect(ExtensionsBrowsePanel.number(50) == "50")
        #expect(ExtensionsBrowsePanel.number(0) == "0")
    }
}
