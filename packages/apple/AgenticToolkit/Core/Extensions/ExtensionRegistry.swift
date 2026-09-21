//
//  ExtensionRegistry.swift
//  AgenticToolkit
//

import Foundation
import OSLog

/// Discovers VS Code extensions from disk, gates them by declared VS Code
/// engine compatibility, and drives their contributions through whatever
/// `ContributionPoint`s the host has registered.
///
/// Modeled on `AIPluginManager` (`AIPluginKit/AIPluginManager.swift`):
/// discovery reads only manifests — it never opens `main`/`browser`, and
/// never `dlopen`s anything, because a VS Code extension's JavaScript is not
/// something this host runs. A bad or malicious manifest can therefore only
/// ever produce a load failure, never code execution.
///
/// Search paths are injected, not derived. `AppStorageLocation` (where the
/// app would normally answer "where do extensions live on disk") is in
/// `apple-database`, a tier this one cannot import without creating an
/// upward dependency — so the caller resolves the real paths and passes
/// them in, exactly as `AIPluginManager`'s test-only initializer does.
@MainActor
public final class ExtensionRegistry {

    // MARK: - Properties

    /// The VS Code API version this host claims to implement. Extensions
    /// whose `engines.vscode` rejects this version fail to load — see
    /// `ExtensionLoadError.engineIncompatible`.
    ///
    /// 1.138.0 is derived, not chosen. The `vscode.d.ts` every adaptor in
    /// `VSCodeAPI/` was written against is the one at the upstream commit
    /// pinned in `docs/planning/vsc-extensions-upstream-pin-manifest.md`,
    /// which is `main` at 1.139.0 — i.e. past the 1.138.0 tag cut, and so
    /// containing the whole of 1.138.0's stable API and none of 1.139.0's
    /// guarantees. Declaring the last version whose surface we have actually
    /// read is the honest claim.
    ///
    /// Claiming low is not the safe direction it looks like. This gate only
    /// ever *refuses* extensions; it cannot make an unimplemented API appear,
    /// because an extension that calls one gets the `NotImplementedLedger`'s
    /// thrown member either way. The previous 1.95.0 bought nothing for that
    /// and cost 13.7% of the floored web extensions in the Open VSX survey
    /// (`Scripts/openvsx_engine_survey.py`) — refused before they could report
    /// what they actually needed.
    /// `nonisolated` because it is a constant, not state: the enclosing class
    /// is `@MainActor` for the mutable registry it holds, and inheriting that
    /// here would mean a caller has to hop to the main actor to read a number
    /// that never changes.
    public nonisolated static let declaredVSCodeVersion =
        SemanticVersion(major: 1, minor: 138, patch: 0)

    public private(set) var extensions: [LoadedExtension] = []

    /// Everything that went wrong, whether or not the extension itself
    /// loaded. An entry does **not** imply the extension is absent from
    /// `extensions`: a `contributionPointFailed` entry names one contribution
    /// a loaded, enabled extension could not install, and its extension is
    /// still in `extensions` and still working in every other respect.
    ///
    /// Rebuilt wholesale by `loadAll()`. Between loads the only entries that
    /// change are `contributionPointFailed` ones, which are re-derived per
    /// directory every time contributions are applied and dropped when the
    /// extension is uninstalled — so a repeated enable/disable cycle cannot
    /// accumulate duplicates, and no entry outlives the directory it names.
    public private(set) var failures: [ExtensionLoadFailure] = []

    /// Every identifier this scan established — the extensions that loaded,
    /// plus the ones that failed *after* their manifest decoded — or `nil`
    /// when some directory's identifier was never learned at all.
    ///
    /// `nil` is not "none". It is "I do not know", and the two must behave
    /// oppositely at any caller that deletes on the strength of an absence
    /// (`ThemeContributionPoint.pruneOrphans`, and the persisted-state
    /// invariant on `ContributionPoint`). A directory whose `package.json`
    /// could not be read or parsed has an identifier this process cannot
    /// recover: the identifier lives *inside* the manifest, and the folder
    /// name is not it — the marketplace installer writes
    /// `publisher.name-version`, but a hand-installed extension, a dev
    /// checkout or a clone is named whatever its author named it, so a path
    /// heuristic would answer wrongest for exactly the extensions someone is
    /// working on. One unnameable directory therefore makes the whole scan
    /// incomplete, which is the honest answer and the safe one.
    ///
    /// Computed from the two stored arrays rather than kept as a third
    /// beside them, so it cannot drift out of step with either — plus
    /// `scanReadEverything`, which is the part the arrays cannot express: a
    /// directory the scan never got far enough to name leaves no trace in
    /// either of them, so "every failure is nameable" is not by itself
    /// evidence that the scan was whole.
    public var establishedIdentifiers: Set<String>? {
        guard scanReadEverything else { return nil }
        guard failures.allSatisfy({ $0.identifier != nil }) else { return nil }
        return Set(extensions.map(\.identifier)).union(failures.compactMap(\.identifier))
    }

    private let searchPaths: [URL]
    private let hostVersion: SemanticVersion
    private var contributionPoints: [ContributionPoint] = []

    /// False until a scan has run to completion over every search path. Set
    /// by `loadAll()` alone: `failures` can only speak for directories the
    /// scan got far enough to *name*, and a search path it could not
    /// enumerate — or a directory whose type it could not read — never
    /// becomes a failure at all. Those directories go missing silently, and
    /// without this flag `establishedIdentifiers` would answer for them
    /// anyway.
    ///
    /// It starts `false`, which also covers a registry `loadAll()` has never
    /// run on: two empty arrays are indistinguishable from a scan that found
    /// nothing, and answering `[]` there is the instruction to delete
    /// everything. No caller does that today; it costs nothing to be right
    /// about it, and this task is entirely about not confusing "none" with
    /// "I do not know".
    private var scanReadEverything = false

    /// Called after any change to what the registered points hold — the end of
    /// `loadAll()`, an enable or disable that actually moved, and an uninstall.
    ///
    /// A contribution point receives its own `apply`/`withdraw` and so already
    /// knows; this is for a host that has to reconcile something *outside* the
    /// points with what they now hold. The document layout is the case that
    /// forced it: a contributed view is registered by `ViewsContributionPoint`,
    /// but nothing can place it until the installed `ComposableTabLayoutSpec`
    /// also names it, and that spec belongs to the host.
    ///
    /// A callback rather than a `@Published` set, because this tier is
    /// Foundation-only and the thing that changed is not expressible here: the
    /// registry knows contributions moved, not which of five kinds. Callers
    /// re-read whatever they care about.
    ///
    /// Fired after the state it describes is already in place, so a callback
    /// that reads `extensions` or asks a point what it holds sees the new
    /// answer, never the old one.
    private var contributionsObservers: [(token: UUID, handler: () -> Void)] = []

    /// Registers `handler`, to be called after every contribution change.
    ///
    /// **A list rather than the one slot this used to be.** More than one
    /// thing watches this — the document layout has to widen before a
    /// contributed view can be placed, and the extension hosts have to
    /// reconcile — and a single slot meant whichever subscribed second
    /// silently un-wired the first. The workaround was for each subscriber to
    /// read the slot, keep what it found and call it on the way through, which
    /// is correct only for as long as every subscriber remembers to do it, and
    /// fails silently on the first one that does not *(explicit-over-implicit)*.
    ///
    /// The returned token is only needed to stop observing; a subscriber that
    /// lives as long as the registry can discard it.
    @discardableResult
    public func addContributionsObserver(_ handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        contributionsObservers.append((token: token, handler: handler))
        return token
    }

    /// Stops calling the handler `token` was returned for. A token that is not
    /// registered — already removed, or never was — is not an error, because
    /// the caller is as often as not a teardown path that cannot be sure
    /// *(idempotency)*.
    public func removeContributionsObserver(_ token: UUID) {
        contributionsObservers.removeAll { $0.token == token }
    }

    /// Tells every observer, in the order they subscribed.
    ///
    /// Over a copy, so an observer that subscribes or unsubscribes from inside
    /// its own handler changes who is called *next* time rather than mutating
    /// the list being walked.
    private func notifyContributionsDidChange() {
        for observer in contributionsObservers {
            observer.handler()
        }
    }

    // MARK: - Initialization

    public init(searchPaths: [URL], hostVersion: SemanticVersion) {
        self.searchPaths = searchPaths
        self.hostVersion = hostVersion
    }

    // MARK: - Contribution points

    /// Registers a contribution point. Must happen before `loadAll()`:
    /// loading does not replay past extensions against points registered
    /// afterward, the same way `AIPluginManager`'s discovery does not
    /// retroactively notify a late caller.
    public func register(_ point: any ContributionPoint) {
        contributionPoints.append(point)
    }

    // MARK: - Loading

    /// Discovers manifests under every search path, decodes them, applies
    /// the engine gate, and applies the contributions of every enabled
    /// extension. Never throws: one bad extension does not sink the rest,
    /// it is recorded in `failures` instead.
    ///
    /// Safe to call more than once: the reset covers the contributions an
    /// earlier call applied as well as the two arrays. Clearing only the
    /// arrays would leave every contribution installed twice while the
    /// registry's own state said once, and the single `withdraw` on a later
    /// disable would leave one copy behind.
    public func loadAll() {
        apply(Self.scan(searchPaths: searchPaths, hostVersion: hostVersion))
    }

    /// `loadAll()` with the disk read off the main actor.
    ///
    /// The same load in every respect a caller can observe — same order, same
    /// failures, same notification to the same observers — differing only in
    /// where the
    /// expensive half happens. The class-level rationale for a synchronous load
    /// is scoped to startup, when this runs once before any window exists; a
    /// rescan after an install runs from a button in a live settings window,
    /// and there the enumeration, the read and the JSONC decode per installed
    /// extension are a stopped run loop for as long as the user's extensions
    /// take. Only what genuinely belongs to this actor — withdrawing and
    /// re-applying contributions, and whatever the contributions observers set
    /// off — stays on it.
    ///
    /// Note that the old contributions stay installed for the duration of the
    /// scan, not withdrawn up front: nothing about a rescan is a request to
    /// spend that time with the user's themes uninstalled.
    /// **A superseded reload does not apply what it read.** Two of these can
    /// be in flight at once — the settings window has a rescan button, an
    /// install finishes and rescans, a search path changes — and each suspends
    /// at its `await` with nothing holding the actor. Whichever scan *finished*
    /// last used to win, which is not the same as whichever *started* last: a
    /// scan begun before an install completed can return after the scan begun
    /// to observe it, and overwrite a correct listing with a stale one. The
    /// registry then reports an extension the user just installed as absent
    /// until something else triggers a reload, and nothing here is wrong
    /// enough to log.
    ///
    /// The generation counter settles it by start order. The loser drops its
    /// result: it has already been re-read by a scan that began later, so the
    /// work is redundant rather than lost, and the winner's `apply` is the one
    /// that fires the contributions observers *(idempotency)*.
    public func reload() async {
        let searchPaths = self.searchPaths
        let hostVersion = self.hostVersion
        await reload {
            await Task.detached(priority: .userInitiated) {
                Self.scan(searchPaths: searchPaths, hostVersion: hostVersion)
            }.value
        }
    }

    /// `reload()` with the scan supplied, so a test can decide the order two
    /// overlapping reloads finish in. The production path is the caller above;
    /// nothing else should need this.
    func reload(performing scan: @Sendable () async -> Scan) async {
        reloadGeneration &+= 1
        let generation = reloadGeneration

        let result = await scan()

        guard generation == reloadGeneration else {
            Self.logger.debug(
                """
                Dropping the result of reload \(generation, privacy: .public): superseded by \
                \(self.reloadGeneration, privacy: .public) while it was scanning.
                """)
            return
        }
        apply(result)
    }

    /// Bumped by each `reload` as it starts, and compared with the local copy
    /// after the scan returns. Monotonic and main-actor-confined, so a
    /// comparison here is a comparison against every reload that began later.
    private var reloadGeneration = 0

    /// Everything a pass over the search paths could read, in the order it read
    /// it, and whether it managed to read all of it.
    ///
    /// A value, and `Sendable`, because that is the whole point: deciding it
    /// touches nothing but the file system, so it can be decided anywhere, and
    /// applying it touches nothing but this actor's state.
    struct Scan: Sendable {

        /// One directory the scan looked at and could say something about.
        /// Directories with no `package.json` are not here at all — see
        /// `read(from:hostVersion:)`.
        struct Directory: Sendable {
            let url: URL
            let outcome: Outcome
        }

        enum Outcome: Sendable {
            case manifest(ExtensionManifest)
            /// - Parameter identifier: whose extension this was, when the
            ///   manifest had already decoded — and `nil` when it had not,
            ///   which is the whole of what `ExtensionLoadFailure.identifier`
            ///   means.
            case failed(ExtensionLoadError, identifier: String?)
        }

        var directories: [Directory] = []

        /// False when a search path exists and would not open, or a directory
        /// entry's own type could not be read. Everything downstream reads
        /// "not seen" as "gone" unless this says the scan was partial.
        var readEverything = true
    }

    /// Reads every manifest under `searchPaths` and applies the engine gate.
    ///
    /// `nonisolated` and static: it is a pure function of the paths and the
    /// host version, which is what lets `reload()` hand it to a detached task.
    /// Nothing here decides anything about *this* registry — duplicate
    /// identifiers, the enabled check and the contribution points all belong to
    /// `apply(_:)`, because all three are state rather than disk.
    nonisolated static func scan(searchPaths: [URL], hostVersion: SemanticVersion) -> Scan {
        let fileManager = FileManager.default
        var scan = Scan()

        for searchPath in searchPaths {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: searchPath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                // Two opposite answers arrive here as the same `throw`, and
                // collapsing them is the whole hazard. A search path that is
                // simply *absent* is the ordinary case — bringing the feature
                // up deliberately does not create the folder — and calling
                // that incomplete would switch pruning off forever for every
                // user who has no extensions. A search path that exists and
                // would not open is the other thing entirely: however many
                // extensions live under it, this scan did not see them, and
                // it must not let anyone reconcile against that silence.
                if fileManager.fileExists(atPath: searchPath.path) {
                    scan.readEverything = false
                }
                continue
            }

            // Sorted, because `contentsOfDirectory` is not. Its order is the
            // file system's, which on APFS is neither alphabetical nor stable
            // across machines or across a reinstall of the same extension —
            // and order decides real outcomes here. Two directories claiming
            // one identifier: which one wins and which is recorded as a
            // duplicate. `extensions` is published in scan order, so a
            // settings list reshuffles itself for no visible reason. A bug
            // reproduces on one machine and not the next.
            for directory in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let isDirectory = (try? directory.resourceValues(
                    forKeys: [.isDirectoryKey]))?.isDirectory
                guard let isDirectory else {
                    // The read itself gave no answer, so this entry's type is
                    // unknown — it may well be an extension folder. `== true`
                    // used to fold this into the ordinary-file case below and
                    // drop it without trace.
                    scan.readEverything = false
                    continue
                }
                // A read that succeeded and said "not a directory" is an
                // ordinary file. That is knowledge, not absence of it, and it
                // leaves the scan complete.
                guard isDirectory else { continue }
                if let read = read(from: directory, hostVersion: hostVersion) {
                    scan.directories.append(read)
                }
            }
        }

        return scan
    }

    /// Turns what a scan read into this registry's state: the extensions it
    /// loaded, the failures it recorded, and the contributions every point
    /// holds.
    ///
    /// Safe to call more than once: the reset covers the contributions an
    /// earlier call applied as well as the two arrays. Clearing only the
    /// arrays would leave every contribution installed twice while the
    /// registry's own state said once, and the single `withdraw` on a later
    /// disable would leave one copy behind.
    private func apply(_ scan: Scan) {
        for loaded in extensions {
            for point in contributionPoints {
                point.withdraw(extensionIdentifier: loaded.identifier)
            }
        }

        extensions = []
        failures = []
        scanReadEverything = scan.readEverything

        var claimedIdentifiers: [String: URL] = [:]

        for directory in scan.directories {
            switch directory.outcome {
            case .failed(let reason, let identifier):
                record(reason, at: directory.url, identifier: identifier)

            case .manifest(let manifest):
                if let existing = claimedIdentifiers[manifest.identifier] {
                    // swiftlint:disable:next line_length
                    logger.warning("Skipping duplicate extension '\(manifest.identifier, privacy: .public)' at \(directory.url.path, privacy: .public); already loaded from \(existing.path, privacy: .public)")
                    record(
                        .duplicateIdentifier(existing: existing.path),
                        at: directory.url,
                        identifier: manifest.identifier
                    )
                    continue
                }
                claimedIdentifiers[manifest.identifier] = directory.url

                let loaded = LoadedExtension(manifest: manifest, directory: directory.url)
                extensions.append(loaded)
                // swiftlint:disable:next line_length
                logger.info("Loaded extension '\(manifest.identifier, privacy: .public)' from \(directory.url.path, privacy: .public)")

                // A manifest with no `contributes` key still reaches every
                // point, with `.empty`. Absent and empty are the same statement
                // — this extension declares nothing — and a point that is never
                // told cannot reconcile away what the *previous* version of the
                // same extension declared, so an update that drops the key
                // would orphan its contributions permanently. See
                // `Contributions.empty` for why nil cannot also mean "failed to
                // decode", which is the fact this rests on.
                guard isEnabled(loaded.identifier) else { continue }
                applyContributions(
                    manifest.contributes ?? .empty, from: manifest, at: directory.url)
            }
        }

        notifyContributionsDidChange()
    }

    /// Reads a single extension directory, answering its decoded manifest or
    /// the reason it has none: an unreadable file, malformed JSON, an
    /// unparsable engine range, or an engine range that rejects `hostVersion`.
    ///
    /// A directory with no `package.json` is not itself a failure — a
    /// search path can hold ordinary non-extension directories (`.DS_Store`
    /// siblings, a README) and none of those are worth surfacing as a load
    /// error. `manifestMissing` stays a case on `ExtensionLoadError` for a
    /// future single-extension lookup (e.g. an install flow resolving one
    /// specific directory), just not for bulk discovery.
    ///
    /// **A folder caught mid-install or mid-update is a real exception to
    /// that, not another harmless example.** Its `package.json` has not
    /// landed yet, so it is silently skipped, the scan still calls itself
    /// complete, and `pruneOrphans` deletes that extension's themes as
    /// departed — along with `activeThemeID` if one of them was selected.
    /// The themes return on the next launch, because `apply` re-imports
    /// every declared theme; **the user's chosen theme does not**, and
    /// nothing tells them why it reset. This is accepted deliberately: the
    /// alternative — treating any directory without a manifest as
    /// unnameable — makes the scan permanently incomplete on any search path
    /// holding one stray folder, which disables pruning for everyone, always.
    /// A rare, transient, self-mostly-healing loss beats a certain,
    /// permanent one.
    /// `nil` for a directory with no `package.json`, which is the one answer
    /// that is neither a load nor a failure.
    private nonisolated static func read(
        from directory: URL, hostVersion: SemanticVersion
    ) -> Scan.Directory? {
        let manifestURL = directory.appendingPathComponent("package.json")

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            // No identifier: the file that carries it could not be read.
            return Scan.Directory(
                url: directory,
                outcome: .failed(.manifestUnreadable(error.localizedDescription), identifier: nil))
        }

        let manifest: ExtensionManifest
        do {
            // Through the JSONC preprocessor, not straight into the decoder.
            // A `package.json` is strict JSON by npm's rules, but this host
            // reads what is *on disk*, and what is on disk was frequently
            // written by VS Code or hand-edited beside a `settings.json` in
            // the same dialect: `//` comments, a trailing comma, a BOM left by
            // a Windows editor. The same three files the theme and snippet
            // readers already tolerate through this exact helper. A manifest
            // rejected here is not a degraded extension — it is an extension
            // that does not exist as far as this host is concerned.
            //
            // Through the localization tables too, because a manifest that
            // ships translations does not contain the English: it contains
            // `%configuration.title%` and puts the words in `package.nls.json`
            // beside it. Resolved here rather than at each of the dozens of
            // places a manifest string is displayed — there is one place the
            // bytes become an `ExtensionManifest`, and everything downstream
            // then holds strings a person can read (`dry`).
            manifest = try JSONDecoder().decode(
                ExtensionManifest.self,
                from: JSONCPreprocessor.jsonData(
                    from: ExtensionManifestLocalization.localize(
                        data, forManifestIn: directory)))
        } catch {
            // The manifest did not decode — but a failure that cannot name its
            // extension sets `establishedIdentifiers` to `nil`, which turns
            // orphan pruning off for *every other* extension in the scan. So
            // before giving up, read `name` and `publisher` out of the raw
            // bytes directly: they are two string fields, they do not depend
            // on the rest of the document being well-formed, and recovering
            // them is the difference between one broken extension and a whole
            // reconciliation pass declining to run.
            return Scan.Directory(
                url: directory,
                outcome: .failed(
                    .manifestMalformed(error.localizedDescription),
                    identifier: identifier(inRawManifest: data)))
        }

        // The manifest decoded, so every failure from here down knows whose
        // extension it is — and must say so. An extension this host will not
        // run is still *installed*, and a caller that reconciles persisted
        // state against "what is installed" would otherwise delete a live
        // extension's contributions on a host downgrade (I2).
        guard let range = VSCodeEngineRange(manifest.engines.vscode) else {
            return Scan.Directory(
                url: directory,
                outcome: .failed(
                    .engineRangeUnparsable(manifest.engines.vscode),
                    identifier: manifest.identifier))
        }

        guard range.accepts(hostVersion) else {
            return Scan.Directory(
                url: directory,
                outcome: .failed(
                    .engineIncompatible(
                        required: manifest.engines.vscode, host: hostVersion.description),
                    identifier: manifest.identifier))
        }

        return Scan.Directory(url: directory, outcome: .manifest(manifest))
    }

    /// - Parameter identifier: whose extension this was, when the manifest
    ///   had already decoded — and `nil` when it had not, which is the whole
    ///   of what `ExtensionLoadFailure.identifier` means. Defaulted so a call
    ///   site with no identifier to give reads as the absence it is rather than
    ///   spelling `nil` and looking like an oversight.
    private func record(_ reason: ExtensionLoadError, at directory: URL, identifier: String? = nil) {
        failures.append(
            ExtensionLoadFailure(directory: directory, reason: reason, identifier: identifier))
        // swiftlint:disable:next line_length
        logger.warning("Failed to load extension at \(directory.path, privacy: .public): \(String(describing: reason), privacy: .public)")
    }

    /// `publisher.name` read out of manifest bytes that did not decode, or
    /// `nil` when even that much is unavailable.
    ///
    /// Deliberately not a second manifest parser: it asks
    /// `JSONSerialization` (through the same JSONC preprocessor the real
    /// decode uses) for the top-level object and reads two string keys. A
    /// document too broken for *that* genuinely has no identity to recover,
    /// and `nil` is then the honest answer — the one that keeps pruning off.
    ///
    /// Folded to lower case to match `ExtensionManifest.identifier`, so a
    /// failure and a successful load of the same extension compare equal.
    private nonisolated static func identifier(inRawManifest data: Data) -> String? {
        guard
            let object = try? JSONCPreprocessor.jsonObject(from: data) as? [String: Any],
            let name = object["name"] as? String,
            !name.isEmpty
        else { return nil }
        guard let publisher = object["publisher"] as? String, !publisher.isEmpty else {
            return name.lowercased()
        }
        return "\(publisher).\(name)".lowercased()
    }

    private func applyContributions(
        _ contributions: ExtensionManifest.Contributions,
        from manifest: ExtensionManifest,
        at directory: URL
    ) {
        // Applying is what decides which contributions of this directory
        // failed, so the previous answer is discarded first rather than added
        // to (`idempotency`). Without this, a re-enable through `setEnabled`
        // — which reaches here with no `loadAll()` in between to clear
        // `failures` — appends a second identical entry every toggle, and a
        // settings panel lists one refusal N times.
        removeContributionFailures(at: directory)

        for point in contributionPoints {
            do {
                try point.apply(contributions, from: manifest, at: directory)
            } catch {
                // swiftlint:disable:next line_length
                logger.error("Contribution point '\(point.contributionKey, privacy: .public)' failed to apply '\(manifest.identifier, privacy: .public)': \(String(describing: error), privacy: .public)")
                // The console is not a UI. This layer collects what went
                // wrong rather than throwing it, so a point that refuses is
                // recorded where a caller can see it — otherwise the
                // extension lists as healthy while a contribution it declared
                // is silently absent. Loading does not abort: the extension
                // stays loaded and the remaining points still apply.
                //
                // `String(describing:)`, not `localizedDescription`. Every
                // conformer of `ContributionPoint` is first-party code in this
                // repo, and a plain `enum … : Error` bridges to an `NSError`
                // whose `localizedDescription` is "The operation couldn't be
                // completed. (Module.SomeError error 0.)" — which names
                // neither the case nor the reason. `String(describing:)` gives
                // the case and its associated values, and it is already this
                // file's idiom for a *recorded* payload (`record(_:at:)`'s log
                // line, `ExtensionManifest.DecodingFailure.reason`). The two
                // Foundation-error cases above keep `localizedDescription`
                // because `CocoaError` and `DecodingError` genuinely localize.
                failures.append(ExtensionLoadFailure(
                    directory: directory,
                    reason: .contributionPointFailed(
                        key: point.contributionKey,
                        message: String(describing: error)
                    ),
                    // This extension loaded and is in `extensions`. A refused
                    // contribution must not make the scan look incomplete —
                    // `everyThemeFailed` is a common entry, and a nil here
                    // would switch off `pruneOrphans` for everyone.
                    identifier: manifest.identifier
                ))
            }
        }
    }

    /// Drops every `contributionPointFailed` entry naming `directory`.
    ///
    /// Scoped to that one case on purpose: the other cases are load-time
    /// verdicts that only `loadAll()` may rebuild, and a directory that
    /// carries one of them never got far enough to apply a contribution.
    private func removeContributionFailures(at directory: URL) {
        failures.removeAll { failure in
            guard failure.directory == directory else { return false }
            if case .contributionPointFailed = failure.reason { return true }
            return false
        }
    }

    // MARK: - Enablement

    /// Whether `identifier` is enabled. Disabled is the tracked state
    /// (`UserSettings.disabledExtensionIdentifiers`), so an identifier this
    /// setting has never seen is enabled by default.
    ///
    /// Case-insensitive, on both sides. `ExtensionManifest.identifier` folds
    /// case, but this set is *persisted* and predates that, so it can still
    /// hold `Ms-Python.Foo` written by an older build — and a caller outside
    /// this file may well pass a display spelling. Comparing raw made a
    /// disable silently stop applying the first time either spelling drifted.
    public func isEnabled(_ identifier: String) -> Bool {
        let folded = identifier.lowercased()
        return !UserSettings.disabledExtensionIdentifiers.value.contains { $0.lowercased() == folded }
    }

    /// Enables or disables `identifier`, applying or withdrawing its
    /// contributions through every registered point in the same call so the
    /// setting and the live contribution state never disagree.
    ///
    /// A call that does not change the state does nothing at all. Callers
    /// re-emit their current value routinely — a `Toggle` bound through a
    /// setter, a settings panel writing every row on save — and applying
    /// twice would leave a contribution point holding two copies of the same
    /// contribution, which one `withdraw` cannot undo.
    public func setEnabled(_ enabled: Bool, for identifier: String) {
        let wasEnabled = isEnabled(identifier)
        guard wasEnabled != enabled else { return }

        // Every case variant goes, then the folded form is what gets written.
        // Removing only the exact spelling the caller passed leaves an older
        // build's differently-cased entry behind, and the extension stays
        // disabled through a re-enable that reported success — the state this
        // whole method exists to keep from happening. It also migrates the
        // persisted set to folded form, one identifier at a time, as the user
        // touches each toggle.
        let folded = identifier.lowercased()
        var disabled = UserSettings.disabledExtensionIdentifiers.value
        disabled = disabled.filter { $0.lowercased() != folded }
        if !enabled {
            disabled.insert(folded)
        }
        UserSettings.disabledExtensionIdentifiers.value = disabled

        guard let loaded = extensions.first(where: { $0.identifier == folded }) else { return }

        if enabled {
            // `.empty` for an absent `contributes`, as at load: re-enabling
            // must put every point back in the same state loading would.
            applyContributions(
                loaded.manifest.contributes ?? .empty, from: loaded.manifest, at: loaded.directory)
        } else {
            for point in contributionPoints {
                point.withdraw(extensionIdentifier: folded)
            }
            // A disabled extension contributes nothing, so a record saying one
            // of its contributions was refused describes a state that no
            // longer exists. Re-enabling re-derives it.
            removeContributionFailures(at: loaded.directory)
        }

        // Only here, past the `guard`s: a call that changed no state and one
        // for an identifier this registry never loaded both leave every point
        // holding exactly what it held, and a host that rebuilt its layout on
        // the strength of that would be doing it on every settings save.
        notifyContributionsDidChange()
    }

    // MARK: - Uninstall

    /// Removes `identifier`'s directory from disk and withdraws its
    /// contributions. Throws only the file-system error; withdrawal itself
    /// cannot fail (see `ContributionPoint.withdraw`).
    ///
    /// An uninstall either happens or it does not. The delete — the one
    /// fallible step — runs first, and everything in memory follows it, so a
    /// throw leaves the extension fully intact: still in `extensions`, still
    /// contributed, still on disk. Half-uninstalled is the worse state,
    /// because the UI would show the extension gone while the next
    /// `loadAll()` resurrects it with no explanation.
    ///
    /// An identifier this registry does not know is not an error — a caller
    /// uninstalling something already gone gets a silent no-op with no side
    /// effects, not a throw.
    public func uninstall(_ identifier: String) throws {
        let folded = identifier.lowercased()
        guard let index = extensions.firstIndex(where: { $0.identifier == folded }) else { return }
        let directory = extensions[index].directory

        try FileManager.default.removeItem(at: directory)

        extensions.remove(at: index)
        for point in contributionPoints {
            point.withdraw(extensionIdentifier: folded)
        }
        // The directory is gone from disk; a failure entry still naming it
        // would point a settings row at nothing. `ExtensionLoadFailure` carries
        // only the directory, so a UI could not even join it back to an
        // identifier to hide it for itself.
        removeContributionFailures(at: directory)

        // Clear the tombstone too. `disabledExtensionIdentifiers` is a set of
        // identifiers, not of installs, so an identifier left in it outlives
        // the extension: reinstalling later comes back disabled with nothing
        // in any UI to explain why, breaking the "freshly installed is on by
        // default" promise the setting is shaped around.
        // Every case variant, for the same reason `setEnabled` removes them
        // all: one left behind is a tombstone that outlives the reinstall.
        var disabled = UserSettings.disabledExtensionIdentifiers.value
        disabled = disabled.filter { $0.lowercased() != folded }
        UserSettings.disabledExtensionIdentifiers.value = disabled

        notifyContributionsDidChange()
    }
}

extension ExtensionRegistry: Loggable {
    public static nonisolated let logger = makeLogger()
}

/// A successfully decoded extension and the directory it was loaded from.
/// `directory` is kept (rather than re-derived) because every contribution
/// path in the manifest is relative to it.
public struct LoadedExtension: Sendable, Equatable {
    public let manifest: ExtensionManifest
    public let directory: URL

    public var identifier: String { manifest.identifier }
}

/// One thing that went wrong for one extension directory, and why. Not
/// necessarily a directory that failed to *load*: `contributionPointFailed`
/// names a single refused contribution of an extension that loaded fine, so a
/// UI rendering this list must read `reason` before it claims the extension is
/// unavailable.
public struct ExtensionLoadFailure: Sendable, Equatable {
    public let directory: URL
    public let reason: ExtensionLoadError
    /// Who lived here — known whenever this failure happened *after* the
    /// manifest decoded, and `nil` exactly when the scan never learned.
    ///
    /// `nil` is what makes a prune unsafe: it is the one state in which "not
    /// among the installed identifiers" and "not installed" stop meaning the
    /// same thing. `ExtensionRegistry.establishedIdentifiers` is where that
    /// distinction is turned into an answer a caller can act on.
    public let identifier: String?

    public init(directory: URL, reason: ExtensionLoadError, identifier: String? = nil) {
        self.directory = directory
        self.reason = reason
        self.identifier = identifier
    }
}

/// Why a load — or one contribution within an otherwise successful load — did
/// not succeed. Every case names enough to explain itself to a user or a log
/// line without re-reading the manifest.
///
/// Every case but the last describes a directory that produced no
/// `LoadedExtension` at all. `contributionPointFailed` is the exception, and
/// it says so on itself.
public enum ExtensionLoadError: Error, Sendable, Equatable {
    case manifestMissing
    case manifestUnreadable(String)
    case manifestMalformed(String)
    case engineRangeUnparsable(String)
    case engineIncompatible(required: String, host: String)
    /// A second directory claiming an identifier an earlier search path had
    /// already loaded. Nothing is wrong with this manifest — `existing` is
    /// the path of the copy that won, because "which one is live" is the only
    /// question a user staring at a duplicate install actually has.
    case duplicateIdentifier(existing: String)
    /// A registered `ContributionPoint` threw from `apply`. `key` is that
    /// point's `contributionKey` and `message` the thrown error's
    /// description: this enum is `Equatable` and so cannot carry an
    /// `any Error`, and a point's identity plus its reason is what a log line
    /// or a settings row needs anyway. The extension itself stayed loaded.
    case contributionPointFailed(key: String, message: String)
}
