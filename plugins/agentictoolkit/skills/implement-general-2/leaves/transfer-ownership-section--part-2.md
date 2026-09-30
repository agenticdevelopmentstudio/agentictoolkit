<!-- leaf: implement-general-2/transfer-ownership-section--part-2 · source: transfer-ownership-section.md -->

# TransferOwnershipSection — continued (part 2)

**Rules** (cite as `implement-general-2/transfer-ownership-section--part-2#<slug>`):

- `trigger-transfer-entitynoun-carry-distinct-accessible-names` MUST — The Disclosure trigger ("Transfer Ownership") and the dropdown trigger ("Transfer {entityNoun}") MUST carry distinct …

## Accessibility

- Root element is a `<section aria-label="Transfer Ownership">`; every interactive control is a
  native, focusable element via the shared `Button`, `DropdownMenuTrigger`/`DropdownMenuItem`, and
  `Input` components this file composes — no bespoke non-semantic clickable element is used.
- The Disclosure trigger ("Transfer Ownership") and the dropdown trigger ("Transfer {entityNoun}")
  MUST carry distinct accessible names, per `trigger-button-labeled-distinctly`, so two buttons in
  the same section are not ambiguous to assistive technology.
- The type-to-confirm `Input` is labeled by an explicit `<Label htmlFor={inputId}>` tied to the
  input via `React.useId()`, not a placeholder alone.
- Keyboard and assistive-technology navigation for the disclosure trigger, the dropdown menu
  (including nested submenus), the dialog, and the input all come from the shared `Disclosure`,
  `DropdownMenu`/`DropdownMenuSub`, `Dialog`, and `Input`/`Button` primitives this file composes —
  no custom key handling (`onKeyDown`, `tabIndex` override) appears in this source, so keyboard
  behavior is that component's own recipe's concern, not this one's.
- Minimum tap target sizing is likewise owned by the shared `Button`, `DropdownMenuItem`, and
  `Input` components this section composes (all `size="sm"` or their defaults); no local
  min-width/min-height override appears in source.
- Contrast is governed by the `apt-*` semantic color tokens this component consumes (`apt-text`,
  `apt-text-muted`, `apt-gold`); no raw hex value or component-specific contrast override appears
  in source.
- The dialog body's transition from "Checking…" to the resolved preview content (or an inline
  error) carries no `aria-live`/`role="status"` region: neither this file nor the shared
  `Dialog`/`DialogContent` primitive it composes (`@agenticdevelopertoolkit/ui/components/dialog`,
  whose `DialogContent` renders a plain `DialogPrimitive.Popup` with no live-region wrapper)
  establishes one, so an assistive-technology user who already opened the dialog gets no signal
  that the content changed without re-reading it.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `entityNoun` | `string` | — | Singular entity noun (e.g. "Persona"), used verbatim in the button and dialog title, and lowercased as `noun = entityNoun.toLowerCase()` for inline prose ("Move this persona…") and the token-count/error fallback text |
| `entityLabel` | `string` | — | The object's own identifier; shown in the dialog and retyped (trimmed) to arm the Transfer button |
| `targets` | `TransferTarget[]` | — | Candidate destinations; team workspaces must already be filtered out by the caller |
| `currentTarget` | `TransferTargetRef` (optional) | `undefined` | The destination the object already lives in; shown disabled in the menu |
| `onPreview` | `(target: TransferTarget) => Promise<TransferPreviewResult>` | — | Server preflight; its result populates the dialog, a throw shows an inline error |
| `onConfirm` | `(target: TransferTarget) => Promise<void>` | — | Performs the transfer; a throw shows an inline error and keeps the dialog open |

### Data Model

- **`TransferTarget`**: `{ slug: string; kind?: "customer" | "organization"; name: string; children?: TransferTarget[] }`.
  `kind` is omitted only for a target that is not a workspace — a nested Product, whose `slug` is
  already globally unique. A non-empty `children` array makes the entry render as a submenu of its
  own `TransferTarget` children.
- **`TransferTargetRef`**: `Pick<TransferTarget, "slug" | "kind">` — enough of a `TransferTarget` to
  identify one, used for `currentTarget`.
- **`TransferPreviewResult`**: `{ tokens: number; revoking: { kind: "user" | "team" | "persona" | "organization" | "app" | "token"; id: string; name: string; via: "role" | "team" | "direct" | "participant" | "group" }[] }`.
  `tokens` is the count of API tokens bound to the object that will be revoked. Each `revoking` entry
  is one principal that will lose access, its `kind`, and `via` — how it currently has access (a
  direct grant, a role, team membership, participant seat, or access-group membership).

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no transition, animation, or motion effect is defined in this file; any open/close motion belongs to the composed `Disclosure`/`Dialog`/`DropdownMenu` components, out of scope here. |
| Increase Contrast | Not applicable: the component uses only semantic `apt-*` color tokens (`apt-text`, `apt-text-muted`, `apt-gold`) and defines no raw hex or opacity-based color of its own that would need a distinct high-contrast variant. |
| Differentiate Without Color | Resolved from source: every state that carries meaning pairs color with text or an icon, never color alone — the token-revocation warning pairs the `TriangleAlert` icon with count text, the current/disabled item appends the text "(current)" rather than relying on a muted color, and the Transfer action's non-destructive nature is conveyed by its "Transfer" label, not by the `warning` variant's color alone (`warning` is itself a color treatment, per `transfer-button-not-destructive-styled`). |

## Privacy

- **Data collected**: The typed confirmation text (`typed`), which the user re-enters as a copy of
  the caller-supplied `entityLabel`; no other input is captured by this component itself.
- **Storage**: None — `chosen`/`preview`/`typed`/`busy`/`error` all live in transient in-memory
  React state (`useState`) and are cleared by `reset()` or on unmount; nothing is written to
  `localStorage`, a cookie, or any persistent store.
- **Transmission**: The component transmits nothing itself; it invokes the caller-supplied
  `onPreview`/`onConfirm` functions with the chosen `TransferTarget`, and any network transmission
  those functions perform is outside this file.
- **Retention**: None beyond the component's own lifetime, or until `reset()` runs — see Storage
  above.

## Platform Notes

- **SwiftUI**: Start from a `DisclosureGroup` for the collapsed/expanded "Transfer Ownership"
  section, a `Menu` with nested `Menu` sub-items for the workspace tree (mirroring
  `DropdownMenuSub`), and a `.sheet`/custom modal for the two-stage (preview then type-to-confirm)
  flow. Drive the confirm gate with a `TextField` bound to `@State` text compared, trimmed, against
  the object's identifier, and use a generation counter alongside the preflight `Task` to discard a
  stale preview the way `previewSeq` does here, since a plain `async` call has no built-in
  "supersede this in-flight request" primitive.
- **Compose**: Use an expand/collapse composable (e.g. driven by `AnimatedVisibility`) for the
  Disclosure equivalent, a `DropdownMenu` with a nested `DropdownMenu` for submenu targets — Compose
  has no native infinitely-nested submenu primitive, so the nested case needs a custom recursive
  composable exactly as this source does — and an `AlertDialog` for the confirm flow. Gate the
  confirm button from a `mutableStateOf` string compared via `.trim()`, and cancel a stale preflight
  `Job` (from a `CoroutineScope`) when a new target is chosen, mirroring the sequence guard here.
- **React/Web**: This is the source. See
  `packages/web/packages/adh-ui/src/blocks/transfer-ownership-section.tsx`, which composes
  `@agenticdevelopertoolkit/ui`'s `Disclosure`, `Button`, `Input`, `Label`, `ErrorText`, the
  `DropdownMenu` family (including `DropdownMenuSub`), and the `Dialog` family. State is plain
  `React.useState`/`useRef`; the async preview-race guard is a manually incremented `previewSeq`
  ref rather than an `AbortController` (no cancellation primitive is used).
- **AppKit/UIKit**: Use an `NSDisclosureButton`/custom expand-collapse `NSView` (AppKit) or a
  collapsible `UITableView` section header (UIKit) for the Disclosure equivalent, and an `NSMenu`/
  `UIMenu` with a nested submenu (`NSMenuItem.submenu`/nested `UIMenu`) for the workspace tree —
  both platforms support native nested submenus, unlike Compose. Use an `NSAlert`/
  `UIAlertController`, or a small custom sheet/panel given the richer body content here, for the
  two-phase confirm; gate the confirm control from a text-field delegate callback compared with
  `.trimmingCharacters(in: .whitespaces)`, and track the in-flight preflight with a generation
  counter checked when its completion handler returns.
- **WinUI 3**: Use an `Expander` (`IsExpanded="False"` by default) for the Disclosure equivalent,
  with its `Header` a horizontal `StackPanel` of a `FontIcon`/`SymbolIcon` (for `ArrowRightLeft`)
  plus a `TextBlock` reading "Transfer Ownership". Inside, a `Button` opens a `MenuFlyout` whose
  `MenuFlyoutItem`s render the leaf targets and whose nested destinations use `MenuFlyoutSubItem` —
  WinUI 3's native nested-submenu control, directly matching `DropdownMenuSub` — with the current
  item's `MenuFlyoutItem.IsEnabled` set `False` and its text carrying " (current)". Model the
  confirmation flow as a `ContentDialog` with `PrimaryButtonText="Transfer"`, binding
  `IsPrimaryButtonEnabled` to the trimmed-match comparison from a `TextBox.TextChanged` handler, and
  suppress dismissal while transferring by handling the dialog's `Closing` event and setting
  `args.Cancel = true` whenever a `confirming` flag is set — the WinUI analogue of the
  `onOpenChange` guard here. Render the "Checking…" text, the token-count warning, and
  the revoked-principal list as conditionally visible `TextBlock`/`ItemsRepeater` content inside the
  `ContentDialog` body, and style the Transfer button with a custom `Style` tinted for the Fluent
  "Caution"/warning system color rather than the built-in destructive/red button style, matching the
  source's `warning`-not-`destructive` choice.

