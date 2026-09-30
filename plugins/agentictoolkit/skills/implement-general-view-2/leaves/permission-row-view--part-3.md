<!-- leaf: implement-general-view-2/permission-row-view--part-3 · source: permission-row-view.md -->

# PermissionRowView — continued (part 3)

## Design Decisions

- **Decision**: hand the pressed action the status displayed at press time
  (`displayedStatus`), not a freshly re-read one.
  **Rationale**: per the source's own doc comment, the display and live TCC
  state can disagree — the user can revoke a permission in System Settings
  while the panel is open — and re-reading at press time would turn a
  button that offered to open System Settings into a live consent prompt
  for a different state than what the user saw and pressed.
  **Approved**: pending
- **Decision**: measure `widestActionWidth` once as a static, process-wide
  probe rather than sizing each button to its own content.
  **Rationale**: per the source's own doc comment, this keeps every row's
  button the same fixed width, so a title change (for example Denied to
  Granted) never reflows the button or the card around it, and the
  measurement is the same for every row since it depends only on the
  titles and the system font.
  **Approved**: pending
- **Decision**: give the row itself no accessibility identifier and no
  accessibility-element status; only the action button is addressable.
  **Rationale**: per the source's own comment, a plain `NSView` is not
  published to accessibility clients by default, and turning the container
  into an accessibility group would add a VoiceOver stop nothing here asks
  for; the button is the real, per-permission handle both tests and
  VoiceOver need.
  **Approved**: pending
- **Decision**: resolve an Automation target's application name via
  `NSWorkspace` inside `PermissionRowView` rather than inside `Permission`.
  **Rationale**: per the source's own comment, `Permission` is
  Foundation-only so a permission-checking daemon process can link it;
  resolving a bundle id to a display name needs `NSWorkspace`, which only
  exists where AppKit is available, so the resolving happens here and is
  handed into `explanation(namingAutomationTarget:)` and `rowTitle(for:)`.
  **Approved**: pending
- **Decision**: ship `card-appearance`'s overlay (3% white background, 6%
  white border) as a fixed, non-semantic color pair rather than an
  appearance-adaptive token.
  **Rationale**: `buildLayout()` sets `layer?.backgroundColor` and
  `layer?.borderColor` to `NSColor.white.withAlphaComponent(...)` with no
  Light Mode or Increase Contrast variant, which only reads as intended
  over a dark host background; recording this as an accepted dark-only
  assumption is more accurate than either calling it done or inventing a
  semantic replacement the source does not have.
  **Approved**: pending
