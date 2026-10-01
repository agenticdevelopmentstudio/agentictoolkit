import Foundation

/// How this bundle may update itself, read from its Info.plist.
///
/// Any bundle with an HTTPS `SUFeedURL` and an `SUPublicEDKey` gets an updater.
/// What it may do on its own depends on `AgenticReleaseChannel`: only a build
/// stamped `release` checks in the background. A developer build installed from
/// a checkout carries `dev` (or nothing) and checks only when its user asks, so
/// it is never replaced by a published build behind its developer's back — and
/// since a dev build normally runs ahead of what is published, an asked-for
/// check usually finds nothing newer.
public struct AppUpdaterConfiguration: Equatable, Sendable {
    public enum Channel: Equatable, Sendable {
        case release
        case dev
    }

    public let feedURL: URL
    public let channel: Channel

    /// Scheduled checks, and Sparkle's "check automatically?" prompt that
    /// precedes them. Release builds only.
    public var checksInBackground: Bool { channel == .release }

    public init?(infoDictionary info: [String: Any]) {
        guard let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:)),
              feed.scheme == "https",
              let key = info["SUPublicEDKey"] as? String, !key.isEmpty
        else { return nil }
        feedURL = feed
        channel = info["AgenticReleaseChannel"] as? String == "release" ? .release : .dev
    }
}
