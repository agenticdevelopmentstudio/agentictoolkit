import Foundation

/// Whether this bundle may update itself, read from its Info.plist.
///
/// Only a build stamped `AgenticReleaseChannel = release` updates. A developer
/// build installed from a checkout carries `dev`, and must never be replaced by
/// a published build behind its developer's back.
public struct AppUpdaterConfiguration: Equatable, Sendable {
    public let feedURL: URL

    public init?(infoDictionary info: [String: Any]) {
        guard info["AgenticReleaseChannel"] as? String == "release",
              let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:)),
              feed.scheme == "https",
              let key = info["SUPublicEDKey"] as? String, !key.isEmpty
        else { return nil }
        feedURL = feed
    }
}
