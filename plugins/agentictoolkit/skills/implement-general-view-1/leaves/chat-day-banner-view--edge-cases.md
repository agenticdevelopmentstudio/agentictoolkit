<!-- leaf: implement-general-view-1/chat-day-banner-view--edge-cases · source: chat-day-banner-view.md -->

# ChatDayBannerView

**Rules** (cite as `implement-general-view-1/chat-day-banner-view--edge-cases#<slug>`):

- `boundary-values` MUST — Two instants on either side of local midnight, as defined by calendar, MUST normalize to different day values via …

## Edge Cases

- **Null/empty input**: Not applicable — `day` is a non-optional Swift `Date`, so the type system guarantees a value is always supplied; there is no null or empty case for the component to guard against.
- **Boundary values (day boundary)**: Two instants on either side of local midnight, as defined by `calendar`, MUST normalize to different `day` values via `calendar.startOfDay(for:)`, even when they are only seconds apart; conversely, two instants many hours apart but on the same calendar day MUST normalize to the same `day` value and render identical banners (see **day-normalized-to-start-of-day**, vector chat-day-banner-003).
- **Concurrent access**: Not applicable — the view is `@MainActor`-isolated; Swift's concurrency checking prevents `day`, the label, and the rules from being read or mutated off the main actor, so there is no concurrent-access case to define.
- **Error states**: Not applicable — construction and theme application are synchronous with no throwing or failable call in `init` or `apply(_:)`; there is nothing in this source that can fail.
- **Offline/disconnected state**: Not applicable — the component performs no networking; its only inputs are the `day`/`calendar` constructor parameters and the current theme palette.
- **Very long formatted date text**: The label has no explicit line-wrap or truncation configured — it uses the default behavior of `NSTextField(labelWithString:)`, a single-line, non-wrapping field. A very long localized date string stays on one line and instead narrows the two rule lines, since the rules (not the label) absorb the remaining horizontal space (see **rules-equal-width**, vector chat-day-banner-015); see the open question on **rule-width-priority**.
- **rule-width-priority**: NEEDS REVIEW: Not implemented in source. No constraint priority is set on the rules' equal-width, leading-gap, or trailing-gap constraints (the `NSLayoutConstraint.activate` call in `init`, all default to required/1000), so a formatted date long enough to force `leadingRule`/`trailingRule` toward negative width has no defined outcome — Auto Layout will break one of several equal-priority required constraints without a specified winner; settling it needs either an explicit priority decision on the rule-width/gap constraints, or a guaranteed maximum width from `AIChatBubbleView.dayFormatter`'s output.
- **Theme change while visible**: Recolors in place via `apply(_:)` (see **theme-responsive-styling**); the day text itself is unaffected, since only font and color are set by `apply(_:)`, not the label's string value.
- **Multiple messages on the same day**: The view itself does not deduplicate or decide when a new day boundary has been reached across a transcript — each instance simply displays the `day` it was constructed with. Per the class's own doc comment ("it is said where it changes and nowhere else"), avoiding duplicate banners for messages that share a day is the caller's responsibility, not this component's.
