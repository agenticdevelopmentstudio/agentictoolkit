<!-- leaf: implement-extension/quick-pick-view-controller--part-3 · source: extension-quick-pick-view-controller.md -->

# ExtensionQuickPickViewController — continued (part 3)

## Design Decisions

- **Decision**: Keep `tableView.allowsMultipleSelection` false even when
  `model.request.canPickMany` is true.
  **Rationale**: "Highlight" always means exactly one row (the arrow-key
  focus), while multi-select is tracked separately through
  `model.checkedIndices` and rendered as a leading checkbox column — never
  through native table multi-row selection — matching the source's own
  design-intent comment about this being the one shape the command
  palette does not need.
  **Approved**: pending
- **Decision**: Hide a separator whose section has no surviving item during
  filtering, rather than mirroring an unverified upstream (VS Code) rule.
  **Rationale**: `ExtensionQuickPickModel`'s own documentation states this
  is "our rule, not a quoted upstream one" and explicitly notes the brief
  did not verify VS Code's own behavior here; documented as a known
  deviation per source-fidelity rather than smoothed over.
  **Approved**: pending
- **Decision**: Re-check `!isSeparator` in `tableView(_:shouldSelectRow:)`
  even though `ExtensionQuickPickModel.highlightRow`/`moveHighlight`
  already refuse to land on a separator.
  **Rationale**: Source documents this as a deliberate belt-and-braces
  redundancy — a second guard against a mouse click doing what the arrow
  keys cannot — and it is kept as observed rather than simplified away.
  **Approved**: pending
- **Decision**: Guard `handleRowClick(_:)` against accepting a stale
  highlight on a separator or out-of-range click, in both the single- and
  multi-select branches.
  **Rationale**: Source documents this guard as the fix for a real prior
  defect — a click on a separator/section heading used to silently accept
  whatever row was highlighted before the click.
  **Approved**: pending
- **Decision**: Document that `SeparatorRowCellView`'s own doc comment
  claims an empty-label separator renders "a plain divider," while the
  implementation only sets `label.isHidden = true` with no additional
  divider line or box drawn.
  **Rationale**: Source-fidelity requires recording a mismatch between a
  source doc comment's claim and its implementation rather than
  idealizing the described-but-unbuilt behavior; an empty-label separator
  is blank space, not a drawn divider line, in this file as written.
  **Approved**: pending
- **Decision**: Note that `searchField.sendsWholeSearchString = false` and
  `searchField.sendsSearchStringImmediately = true` are set even though no
  `target`/`action` is ever assigned to the search field.
  **Rationale**: Filtering is actually driven entirely by
  `NSSearchFieldDelegate.controlTextDidChange`, which already fires on
  every keystroke regardless of these two flags; they configure a
  target-action search-submission behavior this class never wires up, so
  they read as vestigial configuration rather than load-bearing — recorded
  as observed, not treated as a functional requirement.
  **Approved**: pending
