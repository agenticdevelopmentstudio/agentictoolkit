/**
 * THE BUTTON FLOOR EVERY SHIPR DIALOG SETS.
 *
 * The console's dialog buttons were reported as too small to hit. The fix is not a `size` prop
 * threaded through every dialog, every button bar and every shared component in between — that is
 * the same decision made in a hundred places, and it is how the sizes drifted apart to begin with.
 * `Button` reads `--adh-button-min-height` / `--adh-button-min-width` (both default `0px`), so a
 * SURFACE raises the floor once and every descendant button grows: whatever its `size`, including
 * the ones nested components render that the dialog never names.
 *
 * It is applied per surface rather than once on the console, because a dialog is PORTALLED to the
 * document body — a custom property set on the console's own subtree does not inherit into it.
 * Every `DialogContent` in this package carries this, and so does every `AlertModal` it opens
 * (`contentClassName`); a new dialog that forgets it is the one that will look wrong.
 *
 * `size-*` still wins for the icon buttons' HEIGHT — these are minimums, not sizes — and an icon
 * button stays square, because `buttonVariants` redefines the min-width to the min-height on those
 * variants. What changes is only that nothing lands below the floor.
 */
export const SHIPR_DIALOG_SURFACE =
  "[--adh-button-min-height:2.25rem] [--adh-button-min-width:5.5rem]";
