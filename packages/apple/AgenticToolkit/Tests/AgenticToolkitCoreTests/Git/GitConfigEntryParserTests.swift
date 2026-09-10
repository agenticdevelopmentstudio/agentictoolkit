import Foundation
import Testing
@testable import AgenticToolkitCore

@Suite("GitConfigEntry.parse")
struct GitConfigEntryParserTests {
    @Test("splits on NUL and on the first newline")
    func splits() {
        let output = "user.name\nMike\0user.email\nmike@example.com\0core.editor\nvim -f\nextra\0"
        let entries = GitConfigEntry.parse(nullSeparated: output)
        #expect(entries == [
            GitConfigEntry(key: "user.name", value: "Mike"),
            GitConfigEntry(key: "user.email", value: "mike@example.com"),
            GitConfigEntry(key: "core.editor", value: "vim -f\nextra")
        ])
    }

    @Test("a key without a value has an empty value")
    func missingValue() {
        #expect(GitConfigEntry.parse(nullSeparated: "alias.st\0") == [GitConfigEntry(key: "alias.st", value: "")])
    }

    @Test("empty output yields nothing")
    func empty() {
        #expect(GitConfigEntry.parse(nullSeparated: "").isEmpty)
    }
}
