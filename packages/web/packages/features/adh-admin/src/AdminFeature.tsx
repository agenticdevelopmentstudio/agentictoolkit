"use client";

import { RailHostBoundary, StackGroupDetail, useBasePathRoute } from "@agentic-toolkit/resource";

import { ADMIN_PANES, ADMIN_TOPICS, type AdminTopicId } from "./adminTopics";

/**
 * The admin console as a mountable, hierarchical topic/detail feature: one rail of sections
 * (Users, Invitations, Feature Flags, …) beside the selected section's pane.
 *
 * This is the SAME rail `admin.agenticdeveloperhub`'s own `AdminShell` renders, but built on the
 * fleet's shared `StackGroupDetail` / `RailHostBoundary` instead of admin's own
 * `HierarchicalDetailView` call — because unlike the standalone admin site, a host mounting this
 * (the hub, at `/<workspace>/admin`) is ALREADY inside its own merged topic/detail stack, and
 * `RailHostBoundary` + `StackGroupDetail` is what lets this rail join that stack as one more
 * level rather than opening a second, nested one. The admin site keeps its own `AdminShell`
 * rather than switching to this component, because it is not nested inside anything — it IS the
 * top-level stack, and `HierarchicalDetailView` is the right tool for owning one outright.
 *
 * Gating is deliberately NOT this component's job. Whether the signed-in caller may see admin at
 * all, and which of the twelve sections (if fewer than all) they may open, is a host decision —
 * the hub knows the caller's platform role, the admin site's own `(admin)/layout.tsx` already
 * checks it before this ever mounts, and a THIRD host might have a third rule. Baking a check in
 * here would mean every host inherits admin.agenticdeveloperhub's specific notion of who is an
 * admin, which is exactly the coupling extracting this package was meant to remove. A host that
 * needs to hide sections filters `ADMIN_TOPICS` (or `ADMIN_PANES`) before ever reaching this
 * component; this component only ever renders what it is handed.
 */
export function AdminFeature({
  basePath,
  topicId,
}: {
  /** The feature's URL base; every push is `<basePath>/<topicId>`. */
  basePath: string;
  /** The open section, or undefined for the bare topic overview. */
  topicId?: AdminTopicId;
}) {
  const { pushSegment } = useBasePathRoute(basePath);

  return (
    <RailHostBoundary>
      <StackGroupDetail
        levelId="admin-topics"
        title="Admin"
        itemNoun="admin section"
        urlSelection={{ selectedId: topicId ?? null, onSelect: pushSegment }}
        items={ADMIN_TOPICS.map((topic) => {
          const Icon = topic.icon;
          const Pane = ADMIN_PANES[topic.id];
          return {
            id: topic.id,
            label: topic.label,
            description: topic.description,
            icon: <Icon size={16} aria-hidden />,
            // Every member IS its section's detail — none of the twelve publish a further rail of
            // their own — so choosing one is the final choice, same as `leadsTo`'s documented
            // default. Named explicitly anyway so a reader doesn't have to know the default to
            // know this rail never nests.
            leadsTo: "detail",
            render: () => (
              // The section pages were built for the old `<main className="p-8">` / admin site's
              // detail pane, neither of which has padding of its own — restore it here so a pane
              // looks identical whether it renders under the admin site's own AdminShell or under
              // a host's rail (mirrors admin-shell.tsx's own wrapper div exactly).
              <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto p-8">
                <Pane />
              </div>
            ),
          };
        })}
      />
    </RailHostBoundary>
  );
}
