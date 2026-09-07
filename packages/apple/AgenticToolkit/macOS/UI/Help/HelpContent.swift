import Foundation

/// Reference prose for one screen, shown *beside* the thing it explains rather
/// than inline beneath it.
///
/// Keeping it out of the body is the point: a blurb under every control is read
/// once and then costs vertical space forever, which pushes the controls apart
/// and buries the ones below the fold. In a drawer the same words are one click
/// away and can be dismissed for good — and a screen that wants to explain more
/// can, since the length no longer competes with the controls themselves.
///
/// Named for what it is, not for where it started: this began as a settings
/// panel's help and is now what any window's help drawer renders.
public struct HelpContent: Sendable, Equatable {

    /// Ordered to match the screen's own groups top to bottom, so the drawer
    /// can be read alongside the controls it describes.
    public let topics: [Topic]

    public init(topics: [Topic]) {
        self.topics = topics
    }
}

extension HelpContent {

    /// One passage of help. `title` names the group of controls the passage
    /// explains — normally the exact group title from the screen, so the two
    /// columns line up as the reader scans down.
    public struct Topic: Sendable, Equatable {

        public let title: String
        public let body: String

        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }
}
