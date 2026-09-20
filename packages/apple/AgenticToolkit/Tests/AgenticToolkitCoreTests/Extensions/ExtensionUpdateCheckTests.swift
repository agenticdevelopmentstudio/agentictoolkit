import Foundation
import Testing
@testable import AgenticToolkitCore

/// Whether anything installed has a newer version this host could run.
///
/// The word that carries the weight is *could run*. Offering an update that
/// would be refused on install produces a button whose only outcome is a
/// refusal, so a candidate that fails the same installability check the
/// installer applies is not an update — it is the end of that extension's
/// updates for now. Most of what is pinned here is that distinction.
@Suite(.serialized)
struct ExtensionUpdateCheckTests {

    private static let host = SemanticVersion(major: 1, minor: 138, patch: 0)

    private func makeCheck() -> ExtensionUpdateCheck {
        StubbedRegistry.reset()
        return ExtensionUpdateCheck(
            client: OpenVSXClient(
                registryBase: StubbedRegistry.registryBase,
                session: StubbedRegistry.makeSession()),
            hostVersion: Self.host)
    }

    private func installed(
        publisher: String? = "acme",
        name: String = "widget",
        version: String = "1.0.0"
    ) throws -> LoadedExtension {
        var fields = [
            "\"name\": \"\(name)\"",
            "\"version\": \"\(version)\"",
            "\"engines\": { \"vscode\": \"^1.74.0\" }"
        ]
        if let publisher {
            fields.append("\"publisher\": \"\(publisher)\"")
        }
        let manifest = try JSONDecoder().decode(
            ExtensionManifest.self,
            from: Data("{ \(fields.joined(separator: ", ")) }".utf8))
        return LoadedExtension(
            manifest: manifest,
            directory: URL(fileURLWithPath: "/tmp/\(name)"))
    }

    private func published(
        namespace: String = "acme",
        name: String = "widget",
        version: String,
        engine: String = "^1.74.0",
        targetPlatform: String? = nil
    ) -> String {
        var fields = [
            "\"namespace\": \"\(namespace)\"",
            "\"name\": \"\(name)\"",
            "\"version\": \"\(version)\"",
            "\"engines\": { \"vscode\": \"\(engine)\" }",
            "\"downloads\": { \"universal\": \"https://registry.test/w.vsix\" }"
        ]
        if let targetPlatform {
            fields.append("\"targetPlatform\": \"\(targetPlatform)\"")
        }
        return "{ \(fields.joined(separator: ", ")) }"
    }

    // MARK: - Finding an update

    @Test("a newer installable version is an update, carrying both versions")
    func newerVersionIsAnUpdate() async throws {
        let check = makeCheck()
        StubbedRegistry.respond(to: "/acme/widget", json: published(version: "2.0.0"))

        let update = try await check.update(for: try installed(version: "1.0.0"))
        let found = try #require(update)
        #expect(found.identifier == "acme.widget")
        #expect(found.installedVersion == "1.0.0")
        #expect(found.latestVersion == "2.0.0")
    }

    @Test("the same version is not an update")
    func sameVersionIsNotAnUpdate() async throws {
        let check = makeCheck()
        StubbedRegistry.respond(to: "/acme/widget", json: published(version: "1.0.0"))

        let update = try await check.update(for: try installed(version: "1.0.0"))
        #expect(update == nil)
    }

    /// The registry can be *behind* — a version pulled after someone installed
    /// it, a self-hosted mirror mid-sync. Offering that as an update would
    /// propose a downgrade, which is worse than no update check at all.
    @Test("an older published version is not an update")
    func olderPublishedVersionIsNotAnUpdate() async throws {
        let check = makeCheck()
        StubbedRegistry.respond(to: "/acme/widget", json: published(version: "0.9.0"))

        let update = try await check.update(for: try installed(version: "1.0.0"))
        #expect(update == nil)
    }

    /// The registry is addressed by the publisher and name the manifest
    /// declares, not by splitting the case-folded identifier back apart — a
    /// publisher with a dot in its name would split at the wrong place.
    @Test("the lookup uses the manifest's publisher, even when it contains a dot")
    func lookupUsesThePublisherVerbatim() async throws {
        let check = makeCheck()
        StubbedRegistry.respond(
            to: "/my.company/widget",
            json: published(namespace: "my.company", version: "2.0.0"))

        let update = try await check.update(
            for: try installed(publisher: "my.company", version: "1.0.0"))
        #expect(update?.latestVersion == "2.0.0")
        #expect(StubbedRegistry.requestedURLs.first?.path.hasSuffix("/my.company/widget") == true)
    }

    // MARK: - Updates that would be refused are not updates

    @Test("a newer version that raises engines past this host is not offered")
    func newerButIncompatibleIsNotOffered() async throws {
        let check = makeCheck()
        StubbedRegistry.respond(
            to: "/acme/widget", json: published(version: "2.0.0", engine: "^1.200.0"))

        // Newer, and unusable. A button here could only ever refuse.
        let update = try await check.update(for: try installed(version: "1.0.0"))
        #expect(update == nil)
    }

    @Test("a newer platform-specific build is not offered")
    func newerPlatformSpecificIsNotOffered() async throws {
        let check = makeCheck()
        StubbedRegistry.respond(
            to: "/acme/widget",
            json: published(version: "2.0.0", targetPlatform: "darwin-arm64"))

        let update = try await check.update(for: try installed(version: "1.0.0"))
        #expect(update == nil)
    }

    // MARK: - Questions that cannot be answered

    @Test("a manifest with no publisher has no registry coordinate")
    func noPublisherThrows() async throws {
        let check = makeCheck()
        await #expect(throws: ExtensionUpdateError.noPublisher("widget")) {
            _ = try await check.update(for: try self.installed(publisher: nil))
        }
    }

    /// A version string neither side can compare is not an update. Deciding on
    /// string inequality alone would happily propose a downgrade.
    @Test("versions that cannot be compared are an error, not an update")
    func incomparableVersionsThrow() async throws {
        let check = makeCheck()
        StubbedRegistry.respond(
            to: "/acme/widget",
            json: """
            {
              "namespace": "acme", "name": "widget", "version": "nightly-build",
              "downloads": { "universal": "https://registry.test/w.vsix" }
            }
            """)

        await #expect(throws: ExtensionUpdateError.versionNotComparable(
            installed: "1.0.0", published: "nightly-build")) {
            _ = try await check.update(for: try self.installed(version: "1.0.0"))
        }
    }

    // MARK: - A whole pass

    /// An extension installed by hand and never published 404s here every
    /// time. Letting that take down the answer for everything else would make
    /// the feature useless for exactly the people most likely to have one — so
    /// it is reported beside the updates, by name, rather than dropped.
    @Test("one unpublishable extension does not take the whole check down")
    func oneUnknownExtensionDoesNotFailTheCheck() async throws {
        let check = makeCheck()
        StubbedRegistry.respond(
            to: "/acme/current", json: published(name: "current", version: "1.0.0"))
        StubbedRegistry.respond(
            to: "/acme/stale", json: published(name: "stale", version: "3.0.0"))
        // `/acme/private` is deliberately unstubbed: the stub answers 404, the
        // same as the registry would for a dev checkout.

        let report = await check.check([
            try installed(name: "current", version: "1.0.0"),
            try installed(name: "stale", version: "2.0.0"),
            try installed(name: "private", version: "0.1.0")
        ])

        #expect(report.updates.map(\.identifier) == ["acme.stale"])
        #expect(report.updates.first?.latestVersion == "3.0.0")
        #expect(report.notCheckable == [.init(identifier: "acme.private", reason: .notPublished)])
    }

    // MARK: - Why a check could not be made

    /// A registry that answered *something other than 404* has not said the
    /// extension is unknown — it has said nothing at all. Reporting the two as
    /// one leaves a reader whose network is down reading that eleven of their
    /// extensions do not exist, which is both false and alarming
    /// (`explicit-over-implicit`).
    @Test("a registry that fails is unreachable, not a registry with no record")
    func aFailingRegistryIsUnreachableRatherThanUnknown() async throws {
        let check = makeCheck()
        StubbedRegistry.respond(to: "/acme/widget", json: "{}", status: 503)

        let report = await check.check([try installed()])

        #expect(report.updates.isEmpty)
        #expect(
            report.notCheckable == [.init(identifier: "acme.widget", reason: .registryUnreachable)])
    }

    /// Nothing was asked of the registry at all in this one: a manifest with
    /// no `publisher` has no registry coordinate to look anything up by.
    @Test("a manifest with no publisher says so, rather than blaming the registry")
    func aManifestWithNoPublisherSaysSo() async throws {
        let check = makeCheck()

        let report = await check.check([try installed(publisher: nil)])

        #expect(report.notCheckable.map(\.reason) == [.noPublisher])
    }

    /// Both versions exist and the registry answered; they simply cannot be
    /// ordered, so no update can be offered without risking a downgrade.
    @Test("a version neither side can compare says so")
    func anIncomparableVersionSaysSo() async throws {
        let check = makeCheck()
        StubbedRegistry.respond(to: "/acme/widget", json: published(version: "2.0.0"))

        let report = await check.check([try installed(version: "nightly")])

        #expect(
            report.notCheckable
                == [.init(identifier: "acme.widget", reason: .versionNotComparable)])
    }

    @Test("the unavailable are sorted by identifier, like the updates")
    func theUnavailableAreSorted() async throws {
        let check = makeCheck()

        let report = await check.check([
            try installed(publisher: nil, name: "zebra"),
            try installed(publisher: nil, name: "alpha")
        ])

        #expect(report.notCheckable.map(\.identifier) == ["alpha", "zebra"])
    }

    /// Sorted by identifier, because these lookups run concurrently and task
    /// completion order alone would reshuffle the panel between two checks
    /// that found the same thing.
    @Test("results are sorted by identifier, not by which answer arrived first")
    func resultsAreSorted() async throws {
        let check = makeCheck()
        for name in ["zebra", "alpha", "middle"] {
            StubbedRegistry.respond(
                to: "/acme/\(name)", json: published(name: name, version: "2.0.0"))
        }

        let report = await check.check([
            try installed(name: "zebra", version: "1.0.0"),
            try installed(name: "alpha", version: "1.0.0"),
            try installed(name: "middle", version: "1.0.0")
        ])

        #expect(report.updates.map(\.identifier) == ["acme.alpha", "acme.middle", "acme.zebra"])
    }

    @Test("nothing installed is not an error")
    func emptyInputIsEmptyReport() async {
        let check = makeCheck()
        let report = await check.check([])
        #expect(report.updates.isEmpty)
        #expect(report.notCheckable.isEmpty)
    }
}
