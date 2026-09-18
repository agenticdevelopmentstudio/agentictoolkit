//
//  OpenVSXCatalog.swift
//  AgenticToolkit
//

import Foundation

/// The registry's own description of an extension, as the Open VSX API returns
/// it — one summary row from a search, and one full record for a named version.
///
/// **Every URL-shaped field is decoded as `String`, not `URL`.** These come from
/// a third-party registry, and `URL`'s `Decodable` conformance throws on a
/// string it cannot parse — which would mean one extension with a malformed
/// icon URL takes down the decode of the whole search page it appeared in. The
/// computed accessors below parse each one where it is used, so a bad URL costs
/// exactly the thing it names.
public struct OpenVSXSearchEntry: Decodable, Sendable, Equatable {

    public let namespace: String
    public let name: String
    public let version: String
    public let displayName: String?
    public let description: String?
    public let downloadCount: Int?
    public let averageRating: Double?
    public let deprecated: Bool?
    public let verified: Bool?
    public let timestamp: String?

    /// Named artifacts for this version — `download`, `icon`, `sha256`,
    /// `signature`, `publicKey`, `license`, `readme`, and others the registry
    /// may add. Absent entirely on some rows, which is why it is Optional
    /// rather than an empty dictionary: "the registry did not say" and "the
    /// registry said there are none" are not the same answer.
    public let files: [String: String]?

    /// `<namespace>.<name>`, case-folded — the form `ExtensionManifest` and
    /// `ExtensionRegistry` use, so a search row can be joined against what is
    /// installed without either side re-deriving the rule.
    public var identifier: String { "\(namespace).\(name)".lowercased() }

    public var iconURL: URL? { files.flatMap { $0["icon"] }.flatMap(URL.init(string:)) }
}

/// One page of `GET /api/-/search`. `totalSize` is the size of the whole
/// result set, not of this page, which is what a caller needs to know whether
/// to ask for another `offset`.
public struct OpenVSXSearchPage: Decodable, Sendable, Equatable {
    public let offset: Int
    public let totalSize: Int
    public let extensions: [OpenVSXSearchEntry]
}

/// The full record for one version of one extension: `GET /api/<namespace>/<name>`
/// for the latest, or `.../<version>` for a named one.
public struct OpenVSXExtensionDetail: Decodable, Sendable, Equatable {

    public let namespace: String
    public let name: String
    public let version: String
    public let displayName: String?
    public let description: String?

    /// The SPDX identifier the publisher declared, e.g. `MIT`. Empty or absent
    /// for an extension that declared none — which is itself worth showing,
    /// because "no license stated" is a stronger reason to hesitate than any
    /// particular license is.
    public let license: String?

    /// `engines` verbatim. The `vscode` entry is the gate; `npm`, `node` and
    /// friends appear here too and mean nothing to this host.
    public let engines: [String: String]?

    /// Download URLs keyed by target platform — `universal`, `darwin-arm64`,
    /// `linux-x64`, and so on. See `universalDownloadURL` for why only one of
    /// those keys is ever used here.
    public let downloads: [String: String]?

    public let files: [String: String]?

    /// `ui`, `workspace`, `web` — where the publisher says the extension can
    /// run. Advisory only: it is declared by hand, most extensions omit it, and
    /// the fact that actually decides whether this host can run the code is
    /// whether the manifest has a `browser` entry point, which is not knowable
    /// until the archive is open.
    public let extensionKind: [String]?

    public let targetPlatform: String?
    public let categories: [String]?
    public let tags: [String]?
    public let repository: String?
    public let homepage: String?
    public let bugs: String?
    public let downloadCount: Int?
    public let deprecated: Bool?
    public let preview: Bool?
    public let preRelease: Bool?
    public let verified: Bool?
    public let timestamp: String?

    public var identifier: String { "\(namespace).\(name)".lowercased() }

    /// The version as a comparable number, or `nil` when the publisher's
    /// version string is not semver. Open VSX requires semver on publish, so
    /// `nil` here means something has changed at the registry rather than that
    /// the extension is unusual.
    public var semanticVersion: SemanticVersion? { SemanticVersion(version) }

    /// The declared `engines.vscode` range, or `nil` when there is none or it
    /// does not parse. An extension with no `engines.vscode` is not gated —
    /// see `installability(forHostVersion:)`.
    public var engineRange: VSCodeEngineRange? {
        engines.flatMap { $0["vscode"] }.flatMap(VSCodeEngineRange.init)
    }

    /// The platform-independent build, the only one this host can use.
    ///
    /// A platform-specific build exists precisely because it ships a native
    /// binary — a language server executable, a `.node` addon — and this host
    /// runs extensions as web extensions in JavaScriptCore, where nothing can
    /// launch or link one (Decision 1). Installing `darwin-arm64` here would
    /// put megabytes of unloadable Mach-O on disk and then fail at activation,
    /// so the absence of a `universal` build is a refusal before the download,
    /// not a surprise after it.
    public var universalDownloadURL: URL? {
        downloads.flatMap { $0[Self.universalTargetPlatform] }.flatMap(URL.init(string:))
    }

    /// The registry's published SHA-256 of the `.vsix`, as a URL to a file
    /// holding the lowercase hex digest and nothing else.
    public var sha256URL: URL? { fileURL("sha256") }

    /// The detached signature archive (`.sigzip`). Absent for an unsigned
    /// extension, which is common and not by itself disqualifying.
    public var signatureURL: URL? { fileURL("signature") }

    /// The PEM public key the signature above verifies against. Per-publisher
    /// and rotated, which is why it is carried per version rather than pinned.
    public var publicKeyURL: URL? { fileURL("publicKey") }

    /// The extension's own license *text*, as opposed to the `license` SPDX
    /// identifier. Absent when the publisher shipped no license file.
    public var licenseTextURL: URL? { fileURL("license") }

    public var readmeURL: URL? { fileURL("readme") }
    public var iconURL: URL? { fileURL("icon") }

    /// Whether the publisher listed `web` among `extensionKind`. Shown, never
    /// enforced — see the property's own note.
    public var declaresWebExtensionKind: Bool { extensionKind?.contains("web") ?? false }

    /// What would happen if this version were installed now.
    ///
    /// Checked before the download rather than after, because every refusal
    /// here is knowable from metadata alone and a user who is going to be told
    /// "no" should be told before several megabytes cross the network.
    public func installability(forHostVersion host: SemanticVersion) -> OpenVSXInstallability {
        if let platform = targetPlatform, platform != Self.universalTargetPlatform {
            return .platformSpecific(platform)
        }
        guard universalDownloadURL != nil else { return .noUniversalBuild }
        if let declared = engines?["vscode"], !declared.isEmpty {
            guard let range = VSCodeEngineRange(declared) else {
                return .engineRangeUnreadable(declared)
            }
            guard range.accepts(host) else { return .engineIncompatible(range) }
        }
        return .installable
    }

    private func fileURL(_ key: String) -> URL? {
        files.flatMap { $0[key] }.flatMap(URL.init(string:))
    }

    /// The `downloads` and `targetPlatform` value meaning "no native code, runs
    /// anywhere". Spelled once because two properties and one check read it.
    static let universalTargetPlatform = "universal"
}

/// Why a registry version can or cannot be installed into this host, decided
/// from metadata alone.
///
/// A named case per reason rather than a `Bool` plus a message: the settings UI
/// has to say *which* wall an extension hit — "needs VS Code 1.140" and "ships
/// a macOS binary" are different situations with different answers — and a
/// reason assembled as prose at the point of refusal cannot be tested or
/// localized *(explicit-over-implicit)*.
public enum OpenVSXInstallability: Sendable, Equatable {

    case installable

    /// The extension declares an `engines.vscode` range this host's declared
    /// version falls outside. The same gate `ExtensionRegistry` applies on
    /// load, applied early so the refusal costs no download.
    case engineIncompatible(VSCodeEngineRange)

    /// `engines.vscode` was present but is not a range this host can read.
    /// Distinct from `engineIncompatible` because the extension may well be
    /// fine and it is the registry's string that is odd — the carried text is
    /// what a bug report needs.
    case engineRangeUnreadable(String)

    /// The version is built for one platform's native code. The payload is the
    /// registry's own target-platform name, e.g. `darwin-arm64`.
    case platformSpecific(String)

    /// No `universal` entry in `downloads` — nothing to fetch even though the
    /// version exists.
    case noUniversalBuild

    public var isInstallable: Bool { self == .installable }
}
