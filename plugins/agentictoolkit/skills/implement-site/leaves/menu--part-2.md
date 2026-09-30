<!-- leaf: implement-site/menu--part-2 · source: site-menu.md -->

# SiteMenu — continued (part 2)

## Platform Notes

- Files: menu config `websites/shared/adh/src/header/MarketingSiteMenu.tsx` +
  `WorkspaceSiteMenu.tsx` (both compose the shared `hubCoreGroups.ts`); types +
  rendering `SiteMenu.tsx` (auth top section + compose) + `NavigationPopover.tsx`
  (icon slot + inline sub-item indent); icon SSoT
  `websites/shared/adh/src/header/menu-icons.ts`; Recents store + hook
  `websites/shared/adh/src/header/recents.ts`; Workspaces context
  `websites/shared/adh/src/header/workspaces-menu.tsx` (hub filler +
  `hub-workspaces-menu-provider.tsx`); recorder
  `websites/main/hub/src/components/workspace/recents-recorder.tsx`.
- The recorder observes `WorkspaceChromeProvider.mergedLevels`
  (`frontend/src/sites/hub/src/components/workspace/workspace-chrome.tsx`) — the one
  place holding the full current selection path (with labels) for both nav models.
- Demo: `frontend/src/local/ui-showcase/app/page.tsx` — a `site-menu` topic rendering
  both auth states with seeded workspaces + recents.
- Responsive: verify via Playwright at 375 / 768 / 1440; keyboard + pointer.
- Tailwind sources: no new package boundary; icons are lucide (already a dependency
  of `@agentic-toolkit/adh` and externalized by it, so the host supplies the one copy).

## Design Decisions

- **One shared core, two configs.** The menu is already `SiteMenu` →
  `NavigationPopover` driven by two `MenuGroup[]` arrays; "duplicate the layout"
  means extracting the shared Hub core so both configs reuse it and only the top
  section diverges. Avoids the copy-paste drift the two configs risk today.
- **Icons live in one `menu-icons` map.** A single co-located map
  (`header/menu-icons.ts`) keyed by SiteId / route path / chrome key is the one
  authoritative icon per entry — none inline in JSX. Chosen over hanging an `icon`
  field on `SiteDef`: the registry is consumed by ~40 sites, so an added field is a
  higher-blast public-shape change for no current non-menu consumer (YAGNI); the
  map is a small-reversible-decision that can be promoted to `SiteDef` later if a
  card/launcher ever needs the same glyphs. It still satisfies the single-source
  requirement — every row, site or chrome, resolves through `menuIcon(key)`.
- **Inline sub-items are a new row kind, not the existing flyout.** The existing
  `topic` group discloses a side flyout; inline sub-items are always-visible
  indented leaves. They are distinct kinds so Hub can nest visibly while Workspaces
  and Recents still use flyouts.
- **Settle-based Recents, not per-view instrumentation.** Recording after the
  selection stack settles (~1.5s) coalesces drill-through into the final
  destination with one observer and no per-page hooks — see
  `docs/ui/deep-linking-foundation.md`. Records "the eventual destination, not each
  click."
- **localStorage, not a backend.** Recents is inherently ephemeral and per-device;
  the `ftd-storage` pattern already exists for exactly this. No table, no migration
  (YAGNI); a cross-device sync can be added later behind the same store API.
