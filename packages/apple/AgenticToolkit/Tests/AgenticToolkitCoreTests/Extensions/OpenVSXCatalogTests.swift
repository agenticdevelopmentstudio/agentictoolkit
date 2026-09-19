import Foundation
import Testing
@testable import AgenticToolkitCore

/// The registry's records, and the verdict this host reaches from them alone.
///
/// Two separate jobs are under test. The first is decoding: these structures
/// are filled from a third-party server, so the interesting cases are the ones
/// where the server sends something unexpected and the decode has to survive
/// it. The second is `installability(forHostVersion:)`, which is the only
/// thing standing between a user and a download that could never have worked —
/// every case it can return is a refusal someone has to read, so each is
/// pinned here rather than collapsed into a Bool.
@Suite
struct OpenVSXCatalogTests {

    private let host = SemanticVersion(major: 1, minor: 138, patch: 0)

    private func decodeDetail(_ json: String) throws -> OpenVSXExtensionDetail {
        try JSONDecoder().decode(OpenVSXExtensionDetail.self, from: Data(json.utf8))
    }

    // MARK: - Decoding what the registry sends

    @Test("a search page decodes, and one row's bad icon URL does not take the page with it")
    func searchPageSurvivesAMalformedURL() throws {
        let json = """
        {
          "offset": 0,
          "totalSize": 2,
          "extensions": [
            {
              "namespace": "dracula-theme", "name": "theme-dracula", "version": "2.25.1",
              "displayName": "Dracula Theme", "downloadCount": 9000000,
              "files": { "icon": "https://open-vsx.org/icon.png" }
            },
            {
              "namespace": "acme", "name": "broken", "version": "1.0.0",
              "files": { "icon": "http://[bad" }
            }
          ]
        }
        """
        let page = try JSONDecoder().decode(OpenVSXSearchPage.self, from: Data(json.utf8))

        #expect(page.totalSize == 2)
        #expect(page.extensions.count == 2)
        #expect(page.extensions[0].iconURL?.absoluteString == "https://open-vsx.org/icon.png")
        // The whole point of decoding URL-shaped fields as `String`: the bad
        // one costs its own accessor and nothing else. Decoded as `URL` this
        // row would have thrown and taken the other one with it.
        //
        // An unclosed IPv6 host, not a string with spaces: `URL(string:)`
        // percent-encodes spaces on this OS rather than refusing them, so a
        // prose-shaped fixture stopped being malformed to Foundation and
        // stopped testing anything.
        #expect(page.extensions[1].iconURL == nil)
        #expect(page.extensions[1].identifier == "acme.broken")
    }

    /// `files` absent and `files` empty are different answers from the
    /// registry, and the model keeps them apart — which is why it is Optional.
    @Test("an absent files map is not an empty one")
    func absentFilesIsNotEmpty() throws {
        let withNone = try decodeDetail("""
        { "namespace": "acme", "name": "none", "version": "1.0.0" }
        """)
        #expect(withNone.files == nil)
        #expect(withNone.sha256URL == nil)
        #expect(withNone.signatureURL == nil)
        #expect(withNone.publicKeyURL == nil)
        #expect(withNone.licenseTextURL == nil)

        let withEmpty = try decodeDetail("""
        { "namespace": "acme", "name": "empty", "version": "1.0.0", "files": {} }
        """)
        #expect(withEmpty.files == [:])
    }

    @Test("the identifier is case-folded, the way the installed side spells it")
    func identifierIsCaseFolded() throws {
        let detail = try decodeDetail("""
        { "namespace": "Dracula-Theme", "name": "Theme-Dracula", "version": "2.25.1" }
        """)
        #expect(detail.identifier == "dracula-theme.theme-dracula")

        let entry = try JSONDecoder().decode(OpenVSXSearchEntry.self, from: Data("""
        { "namespace": "Dracula-Theme", "name": "Theme-Dracula", "version": "2.25.1" }
        """.utf8))
        // A search row and a detail record for one extension must agree, or a
        // panel cannot tell that the row it is showing is the one installed.
        #expect(entry.identifier == detail.identifier)
    }

    @Test("every named artifact is reachable from files")
    func artifactURLsResolve() throws {
        let detail = try decodeDetail("""
        {
          "namespace": "acme", "name": "widget", "version": "1.0.0",
          "files": {
            "download": "https://open-vsx.org/w.vsix",
            "sha256": "https://open-vsx.org/w.sha256",
            "signature": "https://open-vsx.org/w.sigzip",
            "publicKey": "https://open-vsx.org/key.pem",
            "license": "https://open-vsx.org/LICENSE",
            "readme": "https://open-vsx.org/README.md",
            "icon": "https://open-vsx.org/icon.png"
          }
        }
        """)
        #expect(detail.sha256URL?.lastPathComponent == "w.sha256")
        #expect(detail.signatureURL?.lastPathComponent == "w.sigzip")
        #expect(detail.publicKeyURL?.lastPathComponent == "key.pem")
        #expect(detail.licenseTextURL?.lastPathComponent == "LICENSE")
        #expect(detail.readmeURL?.lastPathComponent == "README.md")
        #expect(detail.iconURL?.lastPathComponent == "icon.png")
    }

    @Test("engines and extensionKind are read as declared, not interpreted")
    func declarationsAreReadAsWritten() throws {
        let detail = try decodeDetail("""
        {
          "namespace": "acme", "name": "widget", "version": "1.0.0",
          "engines": { "vscode": "^1.74.0", "npm": ">=8" },
          "extensionKind": ["ui", "web"]
        }
        """)
        #expect(detail.engineRange?.accepts(host) == true)
        #expect(detail.declaresWebExtensionKind)
        #expect(detail.semanticVersion == SemanticVersion(major: 1, minor: 0, patch: 0))

        let nodeOnly = try decodeDetail("""
        {
          "namespace": "acme", "name": "node", "version": "1.0.0",
          "extensionKind": ["workspace"]
        }
        """)
        #expect(!nodeOnly.declaresWebExtensionKind)
    }

    // MARK: - The verdict

    private func makeDetail(
        namespace: String = "acme",
        name: String = "widget",
        version: String = "1.0.0",
        targetPlatform: String? = nil,
        universalDownload: Bool = true,
        engine: String? = "^1.74.0"
    ) throws -> OpenVSXExtensionDetail {
        var fields: [String] = [
            "\"namespace\": \"\(namespace)\"",
            "\"name\": \"\(name)\"",
            "\"version\": \"\(version)\""
        ]
        if let targetPlatform {
            fields.append("\"targetPlatform\": \"\(targetPlatform)\"")
        }
        if universalDownload {
            fields.append("\"downloads\": { \"universal\": \"https://open-vsx.org/w.vsix\" }")
        }
        if let engine {
            fields.append("\"engines\": { \"vscode\": \"\(engine)\" }")
        }
        return try decodeDetail("{ \(fields.joined(separator: ", ")) }")
    }

    @Test("a universal build inside our engine range is installable")
    func installableCase() throws {
        let verdict = try makeDetail().installability(forHostVersion: host)
        #expect(verdict == .installable)
        #expect(verdict.isInstallable)
    }

    /// A version that raises `engines.vscode` past what this host claims. The
    /// range is carried on the case because a panel has to be able to say
    /// *which* version it wanted.
    @Test("an engine range this host falls outside refuses, carrying the range")
    func engineIncompatible() throws {
        let detail = try makeDetail(engine: "^1.200.0")
        guard case .engineIncompatible(let range) =
            detail.installability(forHostVersion: host) else {
            Issue.record("expected .engineIncompatible")
            return
        }
        #expect(!range.accepts(host))
        #expect(range.accepts(SemanticVersion(major: 1, minor: 200, patch: 0)))
    }

    @Test("an unreadable engine range refuses separately, carrying the string")
    func engineRangeUnreadable() throws {
        // Whitespace inside a range is what upstream's parser rejects, so this
        // is a real string a registry can hold rather than an invented one.
        let detail = try makeDetail(engine: ">= 1.74.0")
        #expect(
            detail.installability(forHostVersion: host)
                == .engineRangeUnreadable(">= 1.74.0"))
    }

    @Test("an empty engines.vscode is not a gate at all")
    func emptyEngineIsUngated() throws {
        let empty = try makeDetail(engine: "")
        #expect(empty.installability(forHostVersion: host) == .installable)

        let absent = try makeDetail(engine: nil)
        #expect(absent.installability(forHostVersion: host) == .installable)
    }

    /// Checked before the range: a `darwin-arm64` build ships native code this
    /// host could never load, whatever version it claims compatibility with.
    @Test("a platform-specific build refuses before the engine is even read")
    func platformSpecificRefusesFirst() throws {
        let detail = try makeDetail(targetPlatform: "darwin-arm64", engine: "^1.74.0")
        #expect(
            detail.installability(forHostVersion: host)
                == .platformSpecific("darwin-arm64"))
    }

    @Test("an explicit universal targetPlatform is not platform-specific")
    func universalTargetPlatformIsFine() throws {
        let detail = try makeDetail(targetPlatform: "universal")
        #expect(detail.installability(forHostVersion: host) == .installable)
    }

    @Test("no universal entry in downloads means there is nothing to fetch")
    func noUniversalBuild() throws {
        let detail = try makeDetail(universalDownload: false)
        #expect(detail.installability(forHostVersion: host) == .noUniversalBuild)
        #expect(detail.universalDownloadURL == nil)
    }
}
