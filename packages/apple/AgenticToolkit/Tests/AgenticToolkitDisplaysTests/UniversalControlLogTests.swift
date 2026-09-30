import Foundation
import Testing
@testable import AgenticToolkitDisplays

@Suite struct UniversalControlLogTests {
    static func fixture() throws -> Data {
        let url = try #require(
            Bundle(for: FixtureAnchor.self).url(forResource: "universalcontrol-configuration", withExtension: "plist")
        )
        let outer = try #require(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
        return try #require(outer["Configuration"] as? Data)
    }

    @Test func decodesChainAndHead() throws {
        let log = try UniversalControlLog(configuration: Self.fixture())
        #expect(log.version == 3)
        #expect(log.entries.count == 52)
        #expect(log.headEntry?.hash == log.head)
        #expect(log.currentLinks.count == 2)
        #expect(Set(log.currentLinks.map(\.edge)) == [0, 3])
    }

    @Test func rejectsGarbage() {
        #expect(throws: RemoteScreenError.self) { try UniversalControlLog(configuration: Data("nope".utf8)) }
    }

    // R1: the brief's "flag Int" field is actually parentCount; the heap can
    // hold merge entries with more than one parent (none does in the
    // fixture, so this is hand-built rather than pulled from it).
    @Test func decodesEntryWithMultipleParentsAndNoRecords() throws {
        let hash = Data(repeating: 0xAB, count: 32)
        let parentOne = Data(repeating: 0x01, count: 32)
        let parentTwo = Data(repeating: 0x02, count: 32)
        let rawEntry: [Any] = [hash, Int64(1000), 2, parentOne, parentTwo, 0]
        let root: [String: Any] = ["vers": 3, "head": hash, "heap": [rawEntry]]
        let configuration = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)

        let log = try UniversalControlLog(configuration: configuration)
        let decoded = try #require(log.entries.first)
        #expect(decoded.parents == [parentOne, parentTwo])
        #expect(decoded.links.isEmpty)
        #expect(log.headEntry?.hash == hash)
    }

    @Test func rejectsEntryWhoseCountsDontMatch() throws {
        let hash = Data(repeating: 0xAB, count: 32)
        // Declares parentCount 1 but only supplies the record count with no parent.
        let rawEntry: [Any] = [hash, Int64(1000), 1, 0]
        let root: [String: Any] = ["vers": 3, "head": hash, "heap": [rawEntry]]
        let configuration = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        #expect(throws: RemoteScreenError.self) { try UniversalControlLog(configuration: configuration) }
    }

    // A huge parentCount must be rejected, not used in arithmetic that could
    // trap on overflow (`3 + parentCount`).
    @Test func rejectsHugeParentCountInsteadOfCrashing() throws {
        let hash = Data(repeating: 0xAB, count: 32)
        let rawEntry: [Any] = [hash, Int64(1000), Int64(Int.max), 0]
        let root: [String: Any] = ["vers": 3, "head": hash, "heap": [rawEntry]]
        let configuration = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        #expect(throws: RemoteScreenError.self) { try UniversalControlLog(configuration: configuration) }
    }

    // A huge recordCount must be rejected, not used in arithmetic that could
    // trap on overflow (`3 + parentCount + 1 + recordCount`).
    @Test func rejectsHugeRecordCountInsteadOfCrashing() throws {
        let hash = Data(repeating: 0xAB, count: 32)
        let rawEntry: [Any] = [hash, Int64(1000), 0, Int64(Int.max)]
        let root: [String: Any] = ["vers": 3, "head": hash, "heap": [rawEntry]]
        let configuration = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        #expect(throws: RemoteScreenError.self) { try UniversalControlLog(configuration: configuration) }
    }

    // R2: currentLinks(of:) is the newest-record-per-display rule (spike
    // Findings row 8), not simply the head entry's links. For the remote
    // display these coincide today, which this test pins.
    @Test func currentLinksOfRemoteDisplayHasBothEdges() throws {
        let log = try UniversalControlLog(configuration: Self.fixture())
        let links = log.currentLinks(of: UniversalControlFixtureRoles.remoteDisplay)
        #expect(links.count == 2)
        #expect(Set(links.map(\.edge)) == [0, 3])
    }
}

/// Class used only to locate the test bundle.
final class FixtureAnchor {}
