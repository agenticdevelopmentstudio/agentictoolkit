<!-- leaf: implement-general-view-2/permissions-panel-view--states · source: permissions-panel-view.md -->

# Permissions Panel View

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders one row per entry in `permissions`, in order, inside the full-bleed vertical stack described in Appearance. |
| Pressed | Not applicable: the panel itself has no pressable surface; each row's own action button owns its pressed state. |
| Disabled | Not applicable: source defines no enabled/disabled toggle or appearance for this component. |
| Focused | Not applicable: source sets no custom focus-ring or key-view-loop behavior on the panel; each row's own focusable button is that row's concern. |
| Loading | Not applicable at this component's level: the panel shows no loading indicator of its own; each row independently reflects its own in-flight refresh (`PermissionRowView`'s "Checking…" state), and the panel only orchestrates when those per-row refreshes are triggered. |
