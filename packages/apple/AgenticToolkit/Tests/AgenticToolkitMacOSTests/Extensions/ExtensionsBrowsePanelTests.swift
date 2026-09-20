import Testing
import AppKit
import Foundation
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The Browse & Install panel's installing, driven a click at a time.
///
/// Every test here builds the panel with an installer it controls: the real one
/// downloads an archive, checks a digest and expands it, none of which a test of
/// *which row is talking to which button* has any business doing. The panel's
/// opening search is answered by a session that refuses every request, so
/// loading the view cannot reach the registry.
///
/// Serialized, and the view is loaded but never put in a window — the same
/// arrangement `ExtensionsSettingsPanelTests` uses, for the same reasons.
@MainActor
@Suite(.serialized)
struct ExtensionsBrowsePanelTests {

    // MARK: - Fixtures

    private func makeDetail(
        _ namespace: String,
        _ name: String,
        version: String
    ) throws -> OpenVSXExtensionDetail {
        let json = """
        {
            "namespace": "\(namespace)",
            "name": "\(name)",
            "version": "\(version)",
            "displayName": "\(name.capitalized)",
            "engines": { "vscode": "^1.74.0" },
            "downloads": {
                "universal": "https://registry.invalid/\(namespace)/\(name)/\(version).vsix"
            }
        }
        """
        return try JSONDecoder().decode(OpenVSXExtensionDetail.self, from: Data(json.utf8))
    }

    private func report(_ updates: [ExtensionUpdate]) -> ExtensionUpdateReport {
        ExtensionUpdateReport(updates: updates, notCheckable: [])
    }

    private func update(
        _ detail: OpenVSXExtensionDetail,
        installed: String
    ) -> ExtensionUpdate {
        ExtensionUpdate(
            identifier: detail.identifier, installedVersion: installed, latest: detail)
    }

    /// Builds the panel, loads its view, and takes the coordinator back out of
    /// `AppFeatureRegistry.shared` afterwards.
    private func withPanel(
        _ body: @MainActor (ExtensionsBrowsePanel, ScriptedInstaller) async throws -> Void
    ) async throws {
        let previousSettings = UserSettings.shared
        UserSettings.shared = UserSettings(with: InMemorySettingsStorageProvider())
        defer { UserSettings.shared = previousSettings }

        let root = try ExtensionFixtures.makeTemporaryDirectory("ExtensionsBrowsePanelTests")
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = ExtensionsCoordinator(
            searchPaths: [root],
            themeStore: ThemeStore(storage: ExtensionTestThemeStorage()),
            viewRegistry: nil
        )
        defer { coordinator.unregister() }

        let installer = ScriptedInstaller()
        let panel = ExtensionsBrowsePanel(
            coordinator: coordinator,
            client: OfflineRegistry.makeClient(),
            onInstalled: {},
            installer: { try await installer.install($0) }
        )
        // Panels are built in `viewDidLoad`; no row exists until the view loads.
        _ = panel.view
        try await body(panel, installer)
    }

    // MARK: - Reading the panel

    private func find<Found: NSView>(_ identifier: String, in panel: NSViewController) throws
        -> Found {
        let matches = panel.view.everySubviewForTesting
            .compactMap { $0 as? Found }
            .filter { $0.accessibilityIdentifier() == identifier }
        return try #require(matches.first, "no \(Found.self) identified \(identifier)")
    }

    private func text(_ identifier: String, in panel: NSViewController) throws -> String {
        let field: NSTextField = try find(identifier, in: panel)
        return field.stringValue
    }

    /// Lets the panel's own tasks run until `condition` holds.
    ///
    /// An install starts a `Task`, which does not run until the test suspends;
    /// yielding rather than sleeping keeps the suite off the clock.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            await Task.yield()
        }
    }

    // MARK: - One install per extension

    @Test("updating a second extension does not abandon the first row")
    func updatingASecondExtensionDoesNotAbandonTheFirstRow() async throws {
        try await withPanel { panel, installer in
            let alpha = try makeDetail("pub", "alpha", version: "1.1.0")
            let beta = try makeDetail("pub", "beta", version: "2.1.0")
            panel.showUpdates(report([
                update(alpha, installed: "1.0.0"),
                update(beta, installed: "2.0.0")
            ]))

            let alphaButton: NSButton = try find("extensions.browse.update.pub.alpha", in: panel)
            let betaButton: NSButton = try find("extensions.browse.update.pub.beta", in: panel)
            alphaButton.performClick(nil)
            await settle { installer.isInstalling("pub.alpha") }
            betaButton.performClick(nil)
            await settle { installer.isInstalling("pub.beta") }

            installer.finish("pub.alpha", version: "1.1.0")
            installer.finish("pub.beta", version: "2.1.0")
            await settle { installer.inFlight.isEmpty }
            await settle {
                (try? text("extensions.browse.update.pub.alpha.status", in: panel))?
                    .hasPrefix("Installed") == true
            }

            #expect(
                try text("extensions.browse.update.pub.alpha.status", in: panel)
                    .hasPrefix("Installed 1.1.0."))
            #expect(
                try text("extensions.browse.update.pub.beta.status", in: panel)
                    .hasPrefix("Installed 2.1.0."))
        }
    }

    @Test("an update row disables its own button while it installs, and no other")
    func anUpdateRowDisablesItsOwnButtonWhileItInstalls() async throws {
        try await withPanel { panel, installer in
            let alpha = try makeDetail("pub", "alpha", version: "1.1.0")
            let beta = try makeDetail("pub", "beta", version: "2.1.0")
            panel.showSelection(beta)
            panel.showUpdates(report([update(alpha, installed: "1.0.0")]))

            let rowButton: NSButton = try find("extensions.browse.update.pub.alpha", in: panel)
            let cardButton: NSButton = try find("extensions.browse.install", in: panel)
            #expect(cardButton.isEnabled)

            rowButton.performClick(nil)
            await settle { installer.isInstalling("pub.alpha") }
            #expect(!rowButton.isEnabled)
            #expect(cardButton.isEnabled)

            installer.finish("pub.alpha", version: "1.1.0")
            await settle { rowButton.isEnabled }
            #expect(rowButton.isEnabled)
        }
    }

    @Test("updating from a row leaves the selected extension on screen")
    func updatingFromARowLeavesTheSelectedExtensionOnScreen() async throws {
        try await withPanel { panel, installer in
            let alpha = try makeDetail("pub", "alpha", version: "1.1.0")
            let gamma = try makeDetail("pub", "gamma", version: "3.0.0")
            panel.showSelection(gamma)
            panel.showUpdates(report([update(alpha, installed: "1.0.0")]))

            let rowButton: NSButton = try find("extensions.browse.update.pub.alpha", in: panel)
            rowButton.performClick(nil)
            await settle { installer.isInstalling("pub.alpha") }
            installer.finish("pub.alpha", version: "1.1.0")
            await settle { installer.inFlight.isEmpty }
            await settle {
                (try? text("extensions.browse.update.pub.alpha.status", in: panel))?
                    .hasPrefix("Installed") == true
            }

            #expect(try text("extensions.browse.selected.name", in: panel) == "Gamma")
            #expect(try text("extensions.browse.selected.status", in: panel).isEmpty)
        }
    }

    @Test("installing the selected extension reports into the selected card")
    func installingTheSelectedExtensionReportsIntoTheSelectedCard() async throws {
        try await withPanel { panel, installer in
            let gamma = try makeDetail("pub", "gamma", version: "3.0.0")
            panel.showSelection(gamma)

            let cardButton: NSButton = try find("extensions.browse.install", in: panel)
            cardButton.performClick(nil)
            await settle { installer.isInstalling("pub.gamma") }
            #expect(!cardButton.isEnabled)

            installer.finish("pub.gamma", version: "3.0.0")
            await settle { cardButton.isEnabled }
            #expect(
                try text("extensions.browse.selected.status", in: panel)
                    .hasPrefix("Installed 3.0.0."))
            #expect(cardButton.isEnabled)
        }
    }
}

// MARK: - Doubles

/// An installer that starts when the panel asks and finishes when the test says.
///
/// Two installs can be in flight at once, which is the whole point: the panel
/// offers an Update button per row, so a test has to be able to hold one open
/// while it starts another.
@MainActor
private final class ScriptedInstaller {

    private var waiting: [String: CheckedContinuation<VSIXInstallation, Error>] = [:]

    var inFlight: Set<String> { Set(waiting.keys) }

    func isInstalling(_ identifier: String) -> Bool { waiting[identifier] != nil }

    func install(_ detail: OpenVSXExtensionDetail) async throws -> VSIXInstallation {
        try await withCheckedThrowingContinuation { continuation in
            waiting[detail.identifier] = continuation
        }
    }

    func finish(_ identifier: String, version: String) {
        guard let continuation = waiting.removeValue(forKey: identifier) else { return }
        continuation.resume(returning: VSIXInstallation(
            identifier: identifier,
            version: version,
            displayName: nil,
            directory: URL(fileURLWithPath: "/tmp/\(identifier)", isDirectory: true),
            verification: VSIXVerification(
                sha256: "0", digest: .notPublished, signature: .notPublished),
            source: .registry(identifier, version: version),
            supersededDirectories: [],
            runnableHere: true
        ))
    }
}

/// A registry client that cannot reach a registry.
///
/// The panel searches as soon as its view loads — deliberately, it is the
/// browse case — and a test suite that let that through would be asking
/// open-vsx.org what its most downloaded extensions are today.
private enum OfflineRegistry {

    static func makeClient() -> OpenVSXClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefusingURLProtocol.self]
        return OpenVSXClient(
            registryBase: URL(string: "https://registry.invalid/api")!,
            session: URLSession(configuration: configuration))
    }

    final class RefusingURLProtocol: URLProtocol {
        override static func canInit(with request: URLRequest) -> Bool { true }
        override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
        override func stopLoading() {}
    }
}

private extension NSView {

    /// Every descendant, depth-first. A row's button is several levels below
    /// the panel's own view.
    var everySubviewForTesting: [NSView] {
        subviews + subviews.flatMap(\.everySubviewForTesting)
    }
}
