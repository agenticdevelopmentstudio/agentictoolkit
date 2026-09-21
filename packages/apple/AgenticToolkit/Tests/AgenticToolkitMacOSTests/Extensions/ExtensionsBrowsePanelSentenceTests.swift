import Testing
import Foundation
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The words a user is given when installing an extension does not work.
///
/// Twenty-five error cases across five types reach one function, and it is the
/// only place in this feature where an internal name becomes something a
/// person reads. Nothing else checks it: the switches are exhaustive, so the
/// compiler catches a *missing* case, but a case that falls into a neighbour's
/// clause, reads as a fragment of Swift, or names the wrong number compiles
/// perfectly and ships.
///
/// Every sentence here is a **clause**, not a sentence — the call sites
/// prefix it ("Not installed: ", "Could not read this extension's record: "),
/// so it starts lowercase and ends with a full stop. That shape is asserted
/// once, over everything, rather than being restated in each case.
@MainActor
struct ExtensionsBrowsePanelSentenceTests {

    private let url = URL(string: "https://open-vsx.org/api/acme/widget")!

    /// Every case of every error type this panel renders, together, so the
    /// shape rules below are checked against all of them rather than against
    /// whichever few someone thought of.
    private var everyRenderedError: [any Error] {
        let registry: [OpenVSXError] = [
            .malformedRegistryURL(url),
            .requestFailed(url, status: 404),
            .requestFailed(url, status: 503),
            .undecodableResponse(url, underlying: "keyNotFound"),
            .artifactNotText(url),
            .artifactNotFetchable(url, scheme: "data"),
            .artifactNotFetchable(url, scheme: ""),
            .responseNotHTTP(url),
            .responseTooLarge(url, limit: OpenVSXClient.defaultMaximumMetadataBytes),
            .artifactTooLarge(url, limit: OpenVSXClient.defaultMaximumArtifactBytes),
            .unsafeIdentity(field: "name", value: "../../evil")
        ]
        let install: [VSIXInstallError] = [
            .registryVersionUnusable(.installable),
            .noPayloadDirectory,
            .manifestUnreadable,
            .manifestMalformed("unexpected token"),
            .identityMismatch(claimed: "acme.widget", found: "acme.other"),
            .engineIncompatible("^1.200.0", host: "1.138.0"),
            .engineRangeUnreadable("sometime"),
            .verificationIncomplete(published: "signature", missing: "public key"),
            .unsafeIdentity(field: "publisher", value: "../.."),
            .couldNotInstall("the disk is full.")
        ]
        let verification: [VSIXVerificationError] = [
            .digestMismatch(expected: "aaa", actual: "bbb"),
            .signatureIncomplete(missing: "public key"),
            .signatureInvalid,
            .signatureArchiveUnreadable("not a zip"),
            .publicKeyUnreadable
        ]
        let archive: [VSIXArchiveError] = [
            .destinationExists(URL(fileURLWithPath: "/tmp/acme.widget-1.0.0")),
            .expansionUnavailable("no ditto"),
            .expansionFailed(status: 2, message: "bad archive"),
            .expansionTimedOut(seconds: 30)
        ]
        return registry + install + verification + archive
            + [ExtensionInstallUnavailable.noSearchPath]
    }

    // MARK: - The shape every one of them has to have

    /// A clause, and a finished one. The three call sites concatenate this
    /// onto a prefix, so a sentence that capitalised itself would read
    /// "Not installed: The registry…" and one without a stop would run into
    /// whatever the label puts after it.
    @Test("every rendered error is a lowercase clause ending in a full stop")
    func everySentenceIsAClause() {
        for error in everyRenderedError {
            let sentence = ExtensionsBrowsePanel.sentence(for: error)
            #expect(!sentence.isEmpty, "\(error) produced nothing")
            #expect(sentence.hasSuffix("."), "\(error) → \(sentence)")
            #expect(sentence.first?.isUppercase != true, "\(error) → \(sentence)")
        }
    }

    /// No case may reach the `default:` fallback, which renders
    /// `localizedDescription` — and for a Swift enum error that is
    /// "The operation couldn't be completed. (AgenticToolkitCore.OpenVSXError
    /// error 4.)". The module name in a settings panel is the failure this
    /// function exists to prevent, so it is asserted directly rather than
    /// inferred from the switch being exhaustive.
    @Test("no rendered error leaks a Swift type name or an error code")
    func noSentenceLeaksSwift() {
        for error in everyRenderedError {
            let sentence = ExtensionsBrowsePanel.sentence(for: error)
            for leak in ["AgenticToolkit", "Error(", "error 0", "couldn't be completed"] {
                #expect(!sentence.contains(leak), "\(error) → \(sentence)")
            }
        }
    }

    /// Distinctness is the property a copy-paste between two adjacent `case`
    /// arms destroys, and the one nothing else would notice: two errors that
    /// read identically make a bug report unanswerable. The pairs that are
    /// deliberately one clause — `manifestUnreadable` and `manifestMalformed`
    /// — are collapsed in the source and so are excluded here by not being
    /// listed twice.
    @Test("errors that mean different things read differently")
    func distinctErrorsReadDistinctly() {
        let distinct: [any Error] = [
            OpenVSXError.malformedRegistryURL(url),
            OpenVSXError.requestFailed(url, status: 404),
            OpenVSXError.requestFailed(url, status: 503),
            OpenVSXError.undecodableResponse(url, underlying: "x"),
            OpenVSXError.artifactNotText(url),
            OpenVSXError.responseNotHTTP(url),
            OpenVSXError.responseTooLarge(url, limit: 8 * 1024 * 1024),
            OpenVSXError.artifactTooLarge(url, limit: 512 * 1024 * 1024),
            VSIXInstallError.noPayloadDirectory,
            VSIXVerificationError.signatureInvalid,
            VSIXVerificationError.digestMismatch(expected: "a", actual: "b"),
            VSIXArchiveError.expansionUnavailable("x"),
            ExtensionInstallUnavailable.noSearchPath
        ]

        let sentences = distinct.map { ExtensionsBrowsePanel.sentence(for: $0) }

        #expect(Set(sentences).count == sentences.count, "\(sentences)")
    }

    // MARK: - The cases that carry a number or a name

    /// The two ceilings are 64× apart, so a sentence that named the other
    /// one's limit would be wrong by that factor — and both clauses are about
    /// a response that kept coming, which is exactly the pair a reader would
    /// merge while tidying. `responseTooLarge` also is not a download being
    /// stopped, and must not say it was.
    @Test("the two size ceilings report their own number and their own event")
    func theTwoCeilingsReadDifferently() {
        let metadata = ExtensionsBrowsePanel.sentence(
            for: OpenVSXError.responseTooLarge(url, limit: 8 * 1024 * 1024))
        let artifact = ExtensionsBrowsePanel.sentence(
            for: OpenVSXError.artifactTooLarge(url, limit: 512 * 1024 * 1024))

        #expect(metadata.contains("8 MB"))
        #expect(!metadata.contains("download"))
        #expect(artifact.contains("512 MB"))
        #expect(artifact.contains("download"))
    }

    /// A registry that answered `"download": "data:…"` and one that answered
    /// an address with no scheme at all are different reports, and the second
    /// cannot be phrased by interpolating an empty string — "pointed at a :
    /// address" names nothing.
    @Test("an address with no scheme is not rendered as an empty one")
    func aSchemelessAddressIsNamed() {
        let named = ExtensionsBrowsePanel.sentence(
            for: OpenVSXError.artifactNotFetchable(url, scheme: "data"))
        let schemeless = ExtensionsBrowsePanel.sentence(
            for: OpenVSXError.artifactNotFetchable(url, scheme: ""))

        #expect(named.contains("data: address"))
        #expect(!schemeless.contains("a : address"))
        #expect(schemeless.contains("no scheme"))
    }

    /// A 404 from this registry means the extension is not published, which
    /// is a different thing to tell a user than "the registry answered 404" —
    /// and every other status is the registry having a problem, which is not
    /// the user's to fix but is theirs to see.
    @Test("a missing extension and a broken registry are different reports")
    func notFoundIsNotJustAStatus() {
        let missing = ExtensionsBrowsePanel.sentence(
            for: OpenVSXError.requestFailed(url, status: 404))
        let broken = ExtensionsBrowsePanel.sentence(
            for: OpenVSXError.requestFailed(url, status: 503))

        #expect(missing.contains("no such extension"))
        #expect(!missing.contains("404"))
        #expect(broken.contains("503"))
    }

    /// The values in these two are the whole content of a bug report against
    /// a registry, so they are named rather than softened into "the registry
    /// sent something unexpected".
    @Test("an unsafe identity names the field and the value")
    func anUnsafeIdentityNamesWhatItSaw() {
        let fromRegistry = ExtensionsBrowsePanel.sentence(
            for: OpenVSXError.unsafeIdentity(field: "name", value: "../../evil"))
        let fromArchive = ExtensionsBrowsePanel.sentence(
            for: VSIXInstallError.unsafeIdentity(field: "publisher", value: "../.."))

        #expect(fromRegistry.contains("name"))
        #expect(fromRegistry.contains("../../evil"))
        #expect(fromArchive.contains("publisher"))
        #expect(fromArchive.contains("../.."))
    }

    /// `couldNotInstall` carries a reason that already *is* a sentence — the
    /// file system's, in the rollback case — so it is passed through whole
    /// rather than wrapped in another clause.
    @Test("a failed install is reported in the words it came with")
    func couldNotInstallPassesItsReasonThrough() {
        let sentence = ExtensionsBrowsePanel.sentence(
            for: VSIXInstallError.couldNotInstall("the disk is full."))

        #expect(sentence == "the disk is full.")
    }

    /// Anything that is not one of the five known types still has to produce
    /// something readable rather than nothing — this is the arm the shape
    /// assertions above deliberately do not cover, because its wording is
    /// `NSError`'s and not this function's.
    @Test("an unrecognised error still produces a description")
    func anUnknownErrorFallsBackToItsDescription() {
        let sentence = ExtensionsBrowsePanel.sentence(
            for: CocoaError(.fileWriteNoPermission))

        #expect(!sentence.isEmpty)
    }
}
