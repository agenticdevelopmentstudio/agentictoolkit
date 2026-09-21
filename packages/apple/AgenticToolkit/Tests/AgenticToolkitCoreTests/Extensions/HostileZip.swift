import Foundation

/// A zip file built byte by byte, so a test can put entry names in it that no
/// archiver will write.
///
/// `VSIXFixtures` builds its archives with `ditto -c -k`, which is the right
/// tool for an archive that is meant to be ordinary — and exactly the wrong one
/// here. Every archiver on this machine sanitises the names that matter: `zip`
/// strips a leading `/` and a leading `../`, and `ditto` has no way to be
/// handed a name at all, only a directory to walk. The names below are the
/// attack, so they have to be written directly into the format.
///
/// Store-only (method 0), no data descriptors, no zip64. A traversal fixture is
/// a handful of bytes; compression would add a second thing that can be wrong
/// about a fixture whose job is to be unambiguous.
enum HostileZip {

    /// One member of the archive.
    struct Entry {
        /// The name **exactly as it goes into the archive** — `../escaped.txt`
        /// and `/tmp/x` are the point.
        let name: String
        /// For a symlink, the target path; for a file, its contents.
        let contents: Data
        /// The `st_mode` the entry carries. `0o120777` is what makes an entry a
        /// symlink rather than a file, which is the second escape shape.
        let mode: UInt32

        static func file(_ name: String, _ text: String = "planted") -> Entry {
            Entry(name: name, contents: Data(text.utf8), mode: 0o100_644)
        }

        static func symlink(_ name: String, to target: String) -> Entry {
            Entry(name: name, contents: Data(target.utf8), mode: 0o120_777)
        }
    }

    /// The archive's bytes.
    ///
    /// Written in the order the format is read: every local header and its data
    /// first, then the central directory that indexes them by offset, then the
    /// record that says where the directory starts.
    static func bytes(of entries: [Entry]) -> Data {
        var payload = Data()
        var directory = Data()

        for entry in entries {
            let name = Data(entry.name.utf8)
            let size = UInt32(entry.contents.count)
            let crc = crc32(entry.contents)
            let offset = UInt32(payload.count)

            append(localHeaderSignature, to: &payload)
            append(versionNeeded, to: &payload)
            append(UInt16(0), to: &payload)            // general purpose flags
            append(UInt16(0), to: &payload)            // method: stored
            append(UInt16(0), to: &payload)            // modification time
            append(UInt16(0), to: &payload)            // modification date
            append(crc, to: &payload)
            append(size, to: &payload)                 // compressed size
            append(size, to: &payload)                 // uncompressed size
            append(UInt16(name.count), to: &payload)
            append(UInt16(0), to: &payload)            // extra field length
            payload.append(name)
            payload.append(entry.contents)

            append(centralHeaderSignature, to: &directory)
            // The high byte is the originating system, and it has to say Unix
            // (3) or the external attributes below are not read as a file mode
            // — which is the whole of what makes an entry a symlink.
            append(versionMadeByUnix, to: &directory)
            append(versionNeeded, to: &directory)
            append(UInt16(0), to: &directory)          // general purpose flags
            append(UInt16(0), to: &directory)          // method: stored
            append(UInt16(0), to: &directory)          // modification time
            append(UInt16(0), to: &directory)          // modification date
            append(crc, to: &directory)
            append(size, to: &directory)               // compressed size
            append(size, to: &directory)               // uncompressed size
            append(UInt16(name.count), to: &directory)
            append(UInt16(0), to: &directory)          // extra field length
            append(UInt16(0), to: &directory)          // comment length
            append(UInt16(0), to: &directory)          // disk number
            append(UInt16(0), to: &directory)          // internal attributes
            append(entry.mode << 16, to: &directory)   // external attributes
            append(offset, to: &directory)
            directory.append(name)
        }

        var archive = payload
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        append(endOfDirectorySignature, to: &archive)
        append(UInt16(0), to: &archive)                // this disk
        append(UInt16(0), to: &archive)                // disk with the directory
        append(UInt16(entries.count), to: &archive)    // entries on this disk
        append(UInt16(entries.count), to: &archive)    // entries in total
        append(UInt32(directory.count), to: &archive)
        append(directoryOffset, to: &archive)
        append(UInt16(0), to: &archive)                // archive comment length
        return archive
    }

    /// Writes the archive and answers where it landed.
    static func write(_ entries: [Entry], into directory: URL, named name: String) throws -> URL {
        let archive = directory.appendingPathComponent(name)
        try bytes(of: entries).write(to: archive)
        return archive
    }

    // MARK: - The format

    private static let localHeaderSignature: UInt32 = 0x0403_4B50
    private static let centralHeaderSignature: UInt32 = 0x0201_4B50
    private static let endOfDirectorySignature: UInt32 = 0x0605_4B50
    private static let versionNeeded: UInt16 = 20
    private static let versionMadeByUnix: UInt16 = 0x031E

    /// Bitwise rather than table-driven: these archives are a few hundred
    /// bytes, and a table is a second thing to get wrong.
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        for shift: UInt32 in [0, 8, 16, 24] {
            data.append(UInt8((value >> shift) & 0xFF))
        }
    }
}
