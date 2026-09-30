<!-- leaf: implement-general-view-1/chat-day-banner-view--test-vectors · source: chat-day-banner-view.md -->

# ChatDayBannerView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| chat-day-banner-001 | day-text-rendered | `day` = an instant on June 3, 2026 | Label text equals "Wednesday, June 3 2026", the day-formatted string for June 3, 2026 |
| chat-day-banner-002 | day-normalized-to-start-of-day | `day` = 2026-06-03T23:59:59, `calendar` = a `Calendar` pinned to a fixed time zone (e.g. UTC) | The `day` property equals `calendar.startOfDay(for:)` of that instant (midnight of June 3 in the pinned time zone), not the raw instant passed in |
| chat-day-banner-003 | day-normalized-to-start-of-day, day-text-rendered | Two instances constructed with `day` = 2026-06-03T00:05:00 and `day` = 2026-06-03T23:50:00, both against the same `calendar` pinned to a fixed time zone (e.g. UTC) | Both instances' `day` property and label text are identical |
| chat-day-banner-004 | label-centered | Any `day`, view given a fixed width | Label's horizontal center coincides with the view's horizontal center |
| chat-day-banner-005 | rules-flank-label | Any `day` | `leadingRule`'s trailing edge sits exactly 10pt from the label's leading edge; `trailingRule`'s leading edge sits exactly 10pt from the label's trailing edge |
| chat-day-banner-006 | rules-equal-width | Two banners with very different label widths (short vs. long formatted date) | In both cases `leadingRule` and `trailingRule` have equal width, and the label remains centered |
| chat-day-banner-007 | vertical-insets | Any `day` | Label's top edge is 16pt from the view's top edge; the view's bottom edge is 8pt below the label's bottom edge |
| chat-day-banner-008 | rule-thickness | Any `day` | Both rules are exactly 1pt tall and vertically centered on the label |
| chat-day-banner-009 | static-text-role | Any `day` | The view's accessibility role is `.staticText` |
| chat-day-banner-010 | label-accessibility-label | `day` = an instant on June 3, 2026 | The label's accessibility label equals its rendered string, "Wednesday, June 3 2026" |
| chat-day-banner-011 | label-accessibility-identifier | Any `day` | The label's accessibility identifier equals `chat-day-banner` |
| chat-day-banner-012 | theme-responsive-styling | View constructed under theme A, then the active theme changes to theme B | Label font becomes theme B's caption font; label text color becomes theme B's `timestampText` color; both rules' color becomes theme B's `divider` color — the view is not re-created |
| chat-day-banner-013 | day-and-title-exposed | `day` = an instant on June 3, 2026, `calendar` pinned to a fixed time zone (e.g. UTC) | `banner.day` equals the normalized start-of-day date; `banner.title` equals the label's current string value |
| chat-day-banner-014 | coder-init-unavailable | Attempt to construct via `ChatDayBannerView(coder:)` (e.g. storyboard/XIB unarchiving) | Calling it is a compile error (`@available(*, unavailable)`); if reached at runtime regardless, the process terminates via `fatalError` |
| chat-day-banner-015 | rules-equal-width | A `day`/locale combination producing an unusually long formatted date string, in a narrow view | Label stays on one line (no wrap); both rules narrow together to absorb the remaining width, staying equal to each other for as long as their combined required width is non-negative |
