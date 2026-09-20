import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// The date, once, across the transcript, in front of the first message of a
/// day.
///
/// ```
/// ──────────────  Saturday, June 3 2026  ──────────────
/// ```
///
/// A per-message timestamp says *when in the day*; nothing in a scrolled feed
/// says **which** day, and without that a transcript read from the top is a
/// clock that keeps starting over. Putting the date on every row would answer it
/// at a hundred times the cost, so it is said where it changes and nowhere else.
///
/// Centred, because it belongs to neither side: it is not something anyone said.
/// The rules either side are what keep a line of ordinary type from reading as a
/// short, speaker-less message.
@MainActor
public final class ChatDayBannerView: NSView {

    private let label = NSTextField(labelWithString: "")
    private let leadingRule = NSView()
    private let trailingRule = NSView()

    /// How much air the banner keeps above and below itself.
    ///
    /// More above than below: the gap is what separates yesterday's last message
    /// from today's first, and it belongs to the break, not to the day it opens.
    private static let topInset: CGFloat = 16
    private static let bottomInset: CGFloat = 8

    /// The gap between the date and each rule.
    private static let ruleGap: CGFloat = 10
    private static let ruleHeight: CGFloat = 1

    /// The day this banner announces, at the start of the reader's own day —
    /// what two messages have to share to belong to the same banner.
    public let day: Date

    /// - Parameters:
    ///   - day: any instant on the day being announced; the banner shows the
    ///     whole date it falls on, in the current calendar.
    ///   - calendar: how a day is bounded. Injected so a test can pin the
    ///     time zone that decides which side of midnight an instant falls on.
    public init(day: Date, calendar: Calendar = .current) {
        self.day = calendar.startOfDay(for: day)
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.staticText)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.stringValue = AIChatBubbleView.dayFormatter.string(from: day)
        label.setAccessibilityLabel(label.stringValue)
        label.accessibilityID("chat-day-banner")

        for rule in [leadingRule, trailingRule] {
            rule.translatesAutoresizingMaskIntoConstraints = false
            rule.wantsLayer = true
        }

        addSubview(leadingRule)
        addSubview(label)
        addSubview(trailingRule)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset),
            bottomAnchor.constraint(equalTo: label.bottomAnchor,
                                    constant: Self.bottomInset),

            // The rules take whatever the date leaves. They are equal to each
            // other rather than each pinned to a margin, which is what keeps the
            // date itself on the centre line whatever it says.
            leadingRule.leadingAnchor.constraint(equalTo: leadingAnchor),
            leadingRule.trailingAnchor.constraint(equalTo: label.leadingAnchor,
                                                  constant: -Self.ruleGap),
            trailingRule.leadingAnchor.constraint(equalTo: label.trailingAnchor,
                                                  constant: Self.ruleGap),
            trailingRule.trailingAnchor.constraint(equalTo: trailingAnchor),
            leadingRule.widthAnchor.constraint(equalTo: trailingRule.widthAnchor),
            leadingRule.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            trailingRule.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            leadingRule.heightAnchor.constraint(equalToConstant: Self.ruleHeight),
            trailingRule.heightAnchor.constraint(equalToConstant: Self.ruleHeight)
        ])

        observeTheme { banner, palette in banner.apply(palette) }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    /// The text on the banner, for a caller that needs to read back what a day
    /// is being called rather than re-derive it.
    public var title: String { label.stringValue }

    private func apply(_ palette: SemanticPalette) {
        // The timestamp's own colour and size: a banner is a timestamp that
        // grew a date, and anything louder competes with what people said.
        label.font = palette.font(.caption)
        label.textColor = palette.nsColor(.timestampText)
        for rule in [leadingRule, trailingRule] {
            rule.layer?.backgroundColor = palette.nsColor(.divider).cgColor
        }
    }
}
