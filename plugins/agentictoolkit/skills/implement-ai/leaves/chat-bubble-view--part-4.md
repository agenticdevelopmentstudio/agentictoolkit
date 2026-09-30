<!-- leaf: implement-ai/chat-bubble-view--part-4 · source: ai-chat-bubble-view.md -->

# AIChatBubbleView — continued (part 4)

## Design Decisions

**Decision**: Message text and the inline timestamp are always set in the app's resolved terminal font (Menlo-Regular 13pt by default, via `TerminalAppearance.resolvedFont(theme:)`), never the theme's general body-text font, in both `.speaker` and `.terminal` styles.
**Rationale**: These bubbles are a written-down terminal conversation — the feed's rows are literally transcripts of sessions running in a terminal — so text set in a different face than the terminal it came from would read as a different program's output. The face is chosen once, for the terminal, and both bubble styles follow it. A consequence traced in this recipe (see Compliance) is that the message text does not scale with the app's general typography size control the way theme body/caption text elsewhere does — only the separate Terminal font-size setting affects it.
**Approved: pending**

**Decision**: In `.terminal` style, `.user` and `.assistant` resolve to the identical fill (the palette's `surface` color) and border (the palette's `border` color), rather than keeping the role-based coloring `.speaker` style uses.
**Rationale**: A one-to-one chat has two speakers and no other way to tell them apart, so coloring by role there *is* the attribution. A merged feed already states who is talking in a header line above every row, so coloring by role again there would spend the window's whole palette repeating a fact already said in words, right beside a session list drawn as inset boxes on the window's surface — which is the shape `.terminal` reuses.
**Approved: pending**

**Decision**: A theme's bubble border role is applied only when the theme explicitly overrides it (`theme.roleOverrides[role.rawValue] != nil`), never merely because the role's default derivation would produce some color.
**Rationale**: Every role resolves to *some* color when a theme leaves it undeclared, so checking the resolved color alone would draw a hairline border around every bubble in every theme. Checking for an explicit override instead limits the border to themes that opted in.
**Approved: pending**

**Decision**: `.error` and `.notice` roles keep their fixed border behavior (always bordered / never bordered) even in `.terminal` style, since **terminal-style-role-fill-override** only applies to `.user` and `.assistant`.
**Rationale**: `.error` and `.notice` are not conversation — they carry no speaker to disambiguate — so they stay on the general semantic danger/secondary-text treatment in every style rather than being folded into the terminal panel's speaker-neutral look.
**Approved: pending**

**Decision**: The expand toggle is a chevron symbol (`chevron.down.circle.fill` / `chevron.up.circle.fill`) rather than words, sized at 22pt, and sits in the bubble's lower-right corner under everything rather than immediately after the point where the text was cut.
**Rationale**: Words would compete with the message they sit under, reading as one more line of the reply; a symbol is recognized rather than read, and at this size is a target hit without aiming. Putting it in a fixed lower-right position, rather than trailing the cut point, means it is the same control in the same place whether the message is cut short or laid out whole, rather than moving to wherever the text happened to stop.
**Approved: pending**

**Decision**: The timestamp uses a fixed `h:mm a` (12-hour, unpadded hour) pattern rather than a locale-derived hour-cycle template.
**Rationale**: The class comment documents this as an intentional glance-legibility choice shared with `ChatTranscriptRowView`'s own timestamp, not an oversight. This is a real divergence from `AgenticDeveloperToolkit`'s `MessageBubbleView`, which derives its timestamp pattern from the locale's own hour-cycle template — `AIChatBubbleView` does not follow that convention, and a reader in a 24-hour-clock locale will still see a 12-hour timestamp here.
**Approved: pending**

**Decision**: `AIChatBubbleView.mouseDown(with:)`, when `isTextSelectable` is `true`, consumes a click on the bubble's own padding without ever calling `super.mouseDown(with:)`; when `isTextSelectable` is `false`, it does call `super.mouseDown(with:)`.
**Rationale**: The text view already keeps presses that land on the text itself. Letting a press on the surrounding padding fall through to the superview would mean a click two points from a word a reader was about to select could dismiss something else entirely — the same gesture, two different outcomes, decided by a couple of points. Consuming it here keeps that from happening only when the bubble is meant to support text selection; a non-selectable bubble has no selection to protect, so it lets the default behavior proceed.
**Approved: pending**

**Decision**: `BubbleTextView.mouseDown(with:)` still calls `onSingleClick` even on a double-click, whenever no `onDoubleClick` handler is registered, because the double-click short-circuit only fires when a handler exists.
**Rationale**: A double-click means "select this word" and, in a feed with a handler wired up, also means "open this conversation." Only one of those can have the gesture; where no handler is waiting for it, the click falls through as an ordinary click (invoking `onSingleClick` and the text view's own default handling), so a reader without that handler wired up still gets ordinary double-click word selection.
**Approved: pending**

**Decision**: `measure(_:width:)`'s line-counting walk stops early if it encounters a zero-length effective range, and `trimming(_:within:width:)` stops removing characters once the remaining string is no longer longer than the ellipsis itself.
**Rationale**: Both are defensive guards against a degenerate text-layout result producing an infinite loop, rather than a claim about how many lines or characters the result is guaranteed to have. They trade a possibly-imprecise line count or an ellipsis-only string for a function call that is guaranteed to return.
**Approved: pending**
