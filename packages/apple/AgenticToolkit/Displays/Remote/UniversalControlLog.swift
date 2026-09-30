import Foundation

/// One edge link between two screens in the Universal Control arrangement.
///
/// `deviceA` is always the lexicographically smaller device id; it is not
/// necessarily the local or the remote side (spike Findings row 3).
public struct UniversalControlLink: Equatable, Sendable {
    public let timestamp: Int64
    public let edge: Int
    public let deviceA: String
    public let displayA: String
    public let deviceB: String
    public let displayB: String
    public let offsetA: Int
    public let offsetB: Int

    /// Memberwise, for building links in tests and for `UniversalControlPlacement.link(...)`.
    init(
        timestamp: Int64, edge: Int, deviceA: String, displayA: String,
        deviceB: String, displayB: String, offsetA: Int, offsetB: Int
    ) {
        self.timestamp = timestamp
        self.edge = edge
        self.deviceA = deviceA
        self.displayA = displayA
        self.deviceB = deviceB
        self.displayB = displayB
        self.offsetA = offsetA
        self.offsetB = offsetB
    }

    init(_ raw: [Any]) throws {
        guard raw.count == 8,
              let timestamp = (raw[0] as? NSNumber)?.int64Value, let edge = (raw[1] as? NSNumber)?.intValue,
              let deviceA = raw[2] as? String, let displayA = raw[3] as? String,
              let deviceB = raw[4] as? String, let displayB = raw[5] as? String,
              let offsetA = (raw[6] as? NSNumber)?.intValue, let offsetB = (raw[7] as? NSNumber)?.intValue
        else { throw RemoteScreenError.unreadable("link record shape") }
        self.timestamp = timestamp
        self.edge = edge
        self.deviceA = deviceA
        self.displayA = displayA
        self.deviceB = deviceB
        self.displayB = displayB
        self.offsetA = offsetA
        self.offsetB = offsetB
    }
}

/// The hash-chained arrangement log in UC's ByHost `Configuration` value.
public struct UniversalControlLog: Equatable, Sendable {
    /// A heap entry. Layout per the controller ruling (R1), which corrects
    /// the plan's `flag`/`parent` fields: `[hash, ts, parentCount,
    /// parent₁…parentₙ, recordCount, record₁…recordₘ]`.
    public struct Entry: Equatable, Sendable {
        public let hash: Data
        public let timestamp: Int64
        public let parents: [Data]
        public let links: [UniversalControlLink]
    }

    public let version: Int
    public let head: Data
    public let entries: [Entry]

    public init(configuration: Data) throws {
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: configuration, format: nil)
        } catch {
            throw RemoteScreenError.unreadable("configuration is not a property list")
        }
        guard let root = object as? [String: Any], let version = (root["vers"] as? NSNumber)?.intValue,
              let head = root["head"] as? Data, let heap = root["heap"] as? [[Any]]
        else { throw RemoteScreenError.unreadable("configuration keys") }
        self.version = version
        self.head = head
        self.entries = try heap.map(Self.entry)
    }

    public var headEntry: Entry? { entries.first { $0.hash == head } }
    /// The arrangement in force at the head entry: its own links only.
    /// For the state of one particular display, use `currentLinks(of:)`
    /// instead — a change to a different display leaves the head's links
    /// stale for displays it doesn't mention (spike Findings row 8).
    public var currentLinks: [UniversalControlLink] { headEntry?.links ?? [] }

    /// The links in force for one display: across every heap entry, the
    /// links that mention `display`, restricted to the newest record
    /// timestamp among them. Implements spike Findings row 8.
    public func currentLinks(of display: String) -> [UniversalControlLink] {
        let mentioning = entries.flatMap(\.links).filter { $0.displayA == display || $0.displayB == display }
        guard let newestTimestamp = mentioning.map(\.timestamp).max() else { return [] }
        var result: [UniversalControlLink] = []
        for link in mentioning where link.timestamp == newestTimestamp {
            if !result.contains(link) { result.append(link) }
        }
        return result
    }

    private static func entry(_ raw: [Any]) throws -> Entry {
        // Bound both counts against `raw.count` before doing arithmetic on
        // them: they come straight from `NSNumber.intValue`, and computing
        // `3 + parentCount` (or worse) before bounding it can trap on
        // integer overflow for a malformed or hostile plist.
        guard raw.count >= 4, let hash = raw[0] as? Data, let timestamp = (raw[1] as? NSNumber)?.int64Value,
              let parentCount = (raw[2] as? NSNumber)?.intValue,
              parentCount >= 0, parentCount <= raw.count - 4
        else { throw RemoteScreenError.unreadable("heap entry shape") }
        let recordCountIndex = 3 + parentCount
        guard let recordCount = (raw[recordCountIndex] as? NSNumber)?.intValue,
              recordCount >= 0, recordCount == raw.count - 4 - parentCount
        else { throw RemoteScreenError.unreadable("heap entry shape") }
        let parents = try raw[3..<recordCountIndex].map { item -> Data in
            guard let data = item as? Data else { throw RemoteScreenError.unreadable("heap entry shape") }
            return data
        }
        let links = try raw[(recordCountIndex + 1)...].map { item -> UniversalControlLink in
            guard let record = item as? [Any] else { throw RemoteScreenError.unreadable("record type") }
            return try UniversalControlLink(record)
        }
        return Entry(hash: hash, timestamp: timestamp, parents: parents, links: links)
    }
}
