<!-- leaf: implement-general-1/key-command-capture-field--part-3 · source: key-command-capture-field.md -->

# KeyCommandCaptureField — continued (part 3)

## Design Decisions

- **Decision**: Draw a bespoke `NSView` and read raw key events directly, instead
  of using an `NSTextField`.
  **Rationale**: Per the source's own doc comment, a field editor would eat the
  very chords being recorded, and `NSTextField`'s own key handling turns
  Cmd-anything into an edit command.
  **Approved**: pending
- **Decision**: Override `performKeyEquivalent(with:)` in addition to
  `keyDown(with:)`.
  **Rationale**: Per the source's own comment, Cmd-chords never reach `keyDown`
  because AppKit offers them down the key-equivalent chain first (a menu
  item, the window), which would otherwise claim them; this override is what
  makes the recorder work for Cmd-combinations at all.
  **Approved**: pending
- **Decision**: Let bare Tab and Shift-Tab pass through uncaptured while
  Option-Tab/Control-Tab remain capturable.
  **Rationale**: Per the source's own comment, a recorder that swallowed either
  bare form would trap anyone who arrived at the field by tabbing through the
  panel, while a modifier-carrying Tab combination is still a legitimate
  chord to record.
  **Approved**: pending
- **Decision**: `endRecording()` forces `isRecording` to `false` unconditionally,
  not only through the responder-chain path `resignFirstResponder()` takes.
  **Rationale**: Per the source's own comment, this is what the hosting row calls
  once an edit is committed or abandoned, to stop recording "without going
  through the responder chain" — necessary because the row, not the field,
  owns commit, and may need to end recording from code that does not itself
  trigger first-responder resignation.
  **Approved**: pending
- **Decision**: While recording, do not switch the label to "Press keys…" if a
  shortcut is already being displayed or pending; only fall back to "Press
  keys…" when neither is set.
  **Rationale**: `refreshText()` resolves text from a single precedence chain
  (`pendingShortcut ?? displayedShortcut`, else "Press keys…" or
  `placeholder`) with no separate "just started recording" branch. This is
  called out because a reader could otherwise assume "Press keys…" always
  appears the instant recording starts.
  **Approved**: pending
