"use client";

import { useRouter } from "next/navigation";
import type { ReactNode } from "react";
import {
  HierarchicalDetailView,
  type TopicDetailItem,
  type TopicLevel,
} from "@agenticdevelopertoolkit/ui/blocks";
import { confirmNavigation } from "@agenticdevelopertoolkit/ui/lib/navigation-guard";
import { SettingsPanel } from "./SettingsPanel";
import { SettingsNavProvider, type SettingsNav } from "./settings-nav";

export interface Topic {
  id: string;
  label: string;
  icon?: ReactNode;
  /** Render a separator row after this item. */
  dividerAfter?: boolean;
  /** Explicit navigation target for this item (each item can route anywhere). */
  href: string;
  /** Dimmed + non-clickable when true (e.g. scoped items while "All" is active). */
  disabled?: boolean;
  content: ReactNode;
}

/**
 * The settings sections as ONE hierarchical topic/detail level — the same stack the rest of the
 * platform renders, and the same shape `admin` uses (`admin/src/components/admin-shell.tsx`).
 *
 * This used to be a hand-rolled `<ul>` of `.settings-nav-item` buttons beside a `.settings-content`
 * pane: a second navigator carrying its own active flag, its own CSS and its own responsive rules,
 * rebuilding what `HierarchicalDetailView` already provides (rail collapse, the icon strip, the
 * disclosure sequence, keyboard handling). `settings.css` went with it — every class in it was
 * written for this file's markup and nothing else, so once the markup left, the whole stylesheet
 * was 34 selectors matching no element on any site. That mattered more here than it did while the
 * sheet was hub's private file: it now reached every site in the fleet through adh-site.css.
 *
 * Five props went at the same time (`slot`, `afterId`, `slotActive`, `contentHeader`,
 * `contentOverride`): all were implemented here but passed by NO caller — not hub's `/settings`
 * (`SettingsTab`), not the User Settings overlay. Their one intended consumer — the Ecosystems
 * tab's active-ecosystem selector — is gone, and the stack expresses the same ideas as `railSlot` /
 * `headerSlot` / `titleActions` if they are ever wanted again.
 *
 * Settings ALWAYS shows a section — `/settings` resolves to the first one (`resolveSettingsTopic`)
 * and the overlay opens on `DEFAULT_SETTINGS_TOPIC` — so `onClear` (re-click-deselect,
 * breadcrumb-up, Back) returns to that default rather than to an empty pane, and the stack's own
 * no-selection nudge never shows here. No breadcrumb: `/settings` already sits under `HomeTabs`,
 * and the overlay under its own DialogTitle.
 */
export function SettingsLayout({
  topics,
  activeId,
  onNavigate,
}: {
  topics: Topic[];
  activeId?: string;
  /** Controlled mode: handle topic selection in-place instead of routing to
   *  `topic.href`. Used by the settings overlay so it can switch sections without
   *  navigating away from the route it's layered over. */
  onNavigate?: (topic: Topic) => void;
}) {
  const router = useRouter();
  const active = topics.find((t) => t.id === activeId) ?? undefined;

  const items: TopicDetailItem[] = topics.map((t) => ({
    id: t.id,
    label: t.label,
    icon: t.icon,
    dividerAfter: t.dividerAfter,
    disabled: t.disabled,
  }));

  // Picking a section. A rail row is a <button> that calls router.push — which the shared
  // UnsavedChangesGuard does NOT intercept (it catches anchor clicks + programmatic navigations
  // that consult confirmNavigation). Uncontrolled (the /settings route), route through
  // confirmNavigation() so switching sections with a dirty panel open prompts Discard/Stay
  // instead of silently dropping the edits; with nothing dirty no guard is registered and it
  // resolves immediately, so ordinary navigation is unaffected.
  //
  // Controlled (the User Settings overlay) hands off UNGATED and returns: that caller runs its
  // own attemptExit/isAnyDirty gate around the section switch, and asking here too would be two
  // alerts for one decision.
  const selectTopic = async (t: Topic): Promise<void> => {
    if (onNavigate) {
      onNavigate(t);
      return;
    }
    if (!(await confirmNavigation())) return;
    router.push(t.href, { scroll: false });
  };

  // Published to the panels so one of them can send the user to a SIBLING section without
  // guessing a URL — see settings-nav.tsx for the 404 that motivated it. It routes through
  // the same selectTopic above, so a host in controlled mode (the overlay) switches in place
  // and a routed host (hub's /settings) navigates, with the dirty-panel gate each already
  // applies. Not memoized: `topics` is rebuilt every render by every caller
  // (buildSettingsTopics()), so a useMemo here would only ever miss.
  const nav: SettingsNav = {
    goToTopic: (topicId) => {
      const target = topics.find((t) => t.id === topicId);
      if (target) void selectTopic(target);
    },
  };

  const levels: TopicLevel[] = [
    {
      id: "settings",
      title: "Settings",
      // Keeps the landmark this surface used to own as its own `<aside aria-label="Settings
      // sections">`. Every rail in the stack is otherwise called "Topic list", so a reader who
      // navigates BY landmark (the User Settings overlay opens over whatever page they were on)
      // would have to guess which of the identically-named regions holds the sections.
      railLabel: "Settings sections",
      items,
      selectedId: active?.id ?? null,
      onSelect: (id) => {
        const t = topics.find((x) => x.id === id);
        if (t) void selectTopic(t);
      },
      // Back to the default section — see the note above on why this is never an empty pane.
      onClear: () => {
        const first = topics[0];
        if (first) void selectTopic(first);
      },
      // …which, on a phone, would make the section list unreachable: the narrow stack's Back
      // clears, this re-selects, and the detail comes straight back. Persistent selection makes
      // that Back reveal the list instead.
      persistentSelection: true,
    },
  ];

  return (
    <SettingsNavProvider value={nav}>
      {/* `showBreadcrumb` defaults to TRUE, so the suppression has to be explicit — see the note
          above on why this surface carries no trail of its own. */}
      <HierarchicalDetailView levels={levels} showBreadcrumb={false}>
        {active?.content && <SettingsPanel>{active.content}</SettingsPanel>}
      </HierarchicalDetailView>
    </SettingsNavProvider>
  );
}
