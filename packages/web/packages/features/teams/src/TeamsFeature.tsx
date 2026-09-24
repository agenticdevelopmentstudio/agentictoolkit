"use client";

import { useCallback, type ReactElement } from "react";
import { useRouter } from "next/navigation";
import { Settings, Users, Shield, UsersRound } from "lucide-react";
import { teamsApi, type Team } from "@agentic-toolkit/data/teams";
import { ecosystemsApi } from "@agentic-toolkit/data/ecosystems";
import {
  useResourceItemQuery,
  useResourceList,
  makeEntityDeleteHandler,
} from "@agentic-toolkit/data";
import {
  ResourceExplorer,
  CreateResourceDialog,
  type ResourceTopic,
} from "@agentic-toolkit/resource";
import { TeamSettingsPane } from "./TeamSettingsPane";
import { TeamMembersPane } from "./TeamMembersPane";
import { TeamPermissionsPane } from "./TeamPermissionsPane";
import { TeamDetail, teamBlank, teamValidate } from "./TeamDetail";

/**
 * The Teams feature workspace (FTD model): a team selector popup whose unselected
 * pane is the frame's select hint, then the entity pane (Team) / Members /
 * Permissions scoped to the selected team. New lives in the popup; Delete lives in
 * the Team pane's Danger zone. Shared wiring lives in ResourceExplorer. Rendered by
 * the host's teams route (the hub's /<slug>/teams/[[...path]]) — a site-less
 * workspace like /organizations.
 */
export function TeamsFeature({
  basePath,
  workspaceSlug: slug,
  all,
  activeTeamId,
  activeTopic,
  activeLeafId,
}: {
  /** The feature's URL base (drives the routes + the list cache key): the host
   *  passes `/<slug>/teams`. Supplied by the host route rather than derived here,
   *  so the same feature mounts under whatever workspace-relative base the host
   *  chooses. */
  basePath: string;
  /** The workspace slug whose (primary) ecosystem scopes the Teams list — the hub
   *  passes its route slug. Like basePath, supplied by the host rather than read
   *  from useParams here, so a host without a [slug] route (a feature site) fails
   *  visibly at the prop seam instead of silently deriving undefined. Absent ⇒ the
   *  list stays in its Loading state (the platform-wide ecosystem-scoping decision
   *  for site mounts — feature-platform-phase2 §2 — is still open). */
  workspaceSlug?: string;
  all?: boolean;
  activeTeamId?: string;
  activeTopic?: string;
  activeLeafId?: string;
}): ReactElement {
  // makeEntityDeleteHandler below (the Danger-zone delete-then-navigate-to-All) takes
  // a raw `{ push }` router — exactly next/navigation's shape — and is the ONLY
  // navigation this file performs; there's no other push here for useBasePathRoute to
  // own, so the plain Next router (not the basePath-specific helpers) is threaded
  // straight through, same as ResourceExplorer does internally for its own pushes.
  const router = useRouter();

  // The Teams list is scoped to the workspace's (primary) ecosystem — the owner of its
  // participant team and of any team created here. `workspaceSlug` is used ONLY for this
  // data-scoping lookup (never for basePath/URL derivation, which the host supplies
  // directly) — resolve slug -> ecosystem id the same way the sibling Ecosystem feature
  // does. It is CACHED per slug: this lookup used to be a plain per-mount fetch, so every visit to
  // Teams paid a round trip before the list could even start — and the round trip's answer never
  // changes for the life of a workspace. The pre-move TeamsTab shared it with the Ecosystem tab's
  // warm cache; this restores the caching without restoring that sharing, which is deliberate —
  // the Ecosystem feature's own `["ecosystem-id-for-slug", slug]` entry documents a phantom-row bug
  // that a second reader of ITS key reopened, and this hook's key space is separate by construction.
  const {
    item: resolvedEcosystemId,
    isSettled: lookupSettled,
    error: lookupError,
  } = useResourceItemQuery<string | null>(
    "workspace:default-ecosystem-id",
    slug ?? null,
    ecosystemsApi.ecosystemIdForSlug,
  );
  const ecosystemId = resolvedEcosystemId ?? undefined;
  // The lookup's terminal non-success states get DEFINED surfaces (never an eternal
  // unlabeled spinner, which reads as an outage): "failed" = the fetch errored (no retry,
  // matching the pre-move `retry: false`); "none" = the slug resolved to a workspace with
  // no primary ecosystem (a first-run tenant). No slug is "pending" and not "none": nothing has
  // been asked, so nothing has been answered, and the branches below already gate on the slug.
  const lookup: "pending" | "resolved" | "failed" | "none" = lookupError
    ? "failed"
    : slug == null || !lookupSettled
      ? "pending"
      : resolvedEcosystemId != null
        ? "resolved"
        : "none";

  // Hold the master list in its Loading state until the ecosystem resolves, so it never
  // fetches (and briefly flashes) the un-scoped set. Once resolved, `load` changes identity
  // and useResourceList refetches the scoped list. A host with NO workspace context at all
  // (a feature-site mount, §2 pending) gets a DEFINED empty state instead of an eternal
  // spinner — an unexplained permanent "Loading…" reads as an outage, not a pending decision.
  const load = useCallback(
    () =>
      ecosystemId
        ? teamsApi.list(ecosystemId)
        : slug != null && lookup === "pending"
          ? new Promise<Team[]>(() => {}) // slug resolving: leave items = null (Loading…)
          : Promise.resolve<Team[]>([]), // unscoped / failed / no-ecosystem: defined empty state
    [ecosystemId, slug, lookup],
  );
  const { items: teams, reload, error } = useResourceList(basePath, load);
  // Creation can only ever succeed where an ecosystem can resolve: a slugged host whose
  // lookup hasn't terminally failed. (While "pending" the list itself is still Loading,
  // so the affordance is unreachable anyway.)
  const canCreate = slug != null && lookup !== "failed" && lookup !== "none";

  // What the team IS comes first — Members, then Permissions — and its Settings last. The topic
  // used to lead, labelled "Team", which restated the row you had just picked and put the least
  // used pane in the most reachable place. The id is unchanged (`settings`), so every deep link
  // still resolves; only the label and the position moved.
  const topics: ResourceTopic[] = [
    {
      id: "members",
      label: "Members",
      icon: <Users size={16} aria-hidden />,
      render: (teamId, titleFor, leaf) => (
        <TeamMembersPane teamId={teamId} title={titleFor("Members")} leaf={leaf} />
      ),
    },
    {
      id: "permissions",
      label: "Permissions",
      icon: <Shield size={16} aria-hidden />,
      render: (_teamId, titleFor, leaf) => (
        <TeamPermissionsPane workspaceSlug={slug} title={titleFor("Permissions")} leaf={leaf} />
      ),
    },
    {
      id: "settings",
      label: "Settings",
      icon: <Settings size={16} aria-hidden />,
      render: (teamId, titleFor) => (
        <TeamSettingsPane
          teamId={teamId}
          items={teams}
          ecosystemId={ecosystemId}
          refresh={reload}
          loadError={error}
          title={titleFor("Settings")}
          onDelete={
            teamId
              ? makeEntityDeleteHandler({
                  basePath,
                  id: teamId,
                  router,
                  del: teamsApi.delete,
                  reload,
                })
              : undefined
          }
        />
      ),
    },
  ];

  return (
    <ResourceExplorer
      all={all}
      activeId={activeTeamId}
      activeTopic={activeTopic}
      activeLeafId={activeLeafId}
      basePath={basePath}
      items={teams}
      getId={(t) => t.id}
      getLabel={(t) => t.displayName}
      nameSuffix="Team"
      itemIcon={<UsersRound size={16} aria-hidden />}
      topics={topics}
      // Creation is suppressed whenever it could never succeed on this host: an unscoped
      // site mount (§2 pending) or a workspace whose ecosystem failed to resolve / doesn't
      // exist — otherwise the rail offers a dialog whose create is permanently rejected.
      newLabel={canCreate ? "New Team…" : undefined}
      rail={{
        title: "All teams",
        help: "Pick a team to manage its settings, members, and permissions.",
        // No `getSublabel`. It showed the identifier under every name, which is a
        // fact about the team a reader needs exactly twice — when checking a collision before
        // naming a new one, and when reading a URL — and it is on the Settings pane both times.
        // On the list it doubled every row's height to disambiguate names that are almost never
        // ambiguous.
        // A failed list leaves `items` null forever (`useResourceList` sets the error and
        // never fills the array), so without this the rail would sit on "Loading…" and the
        // error would be invisible — the rail is the only surface that can show it.
        loadError: error,
        emptyLabel:
          slug == null
            ? "Teams aren't available on this site yet — open them from your hub workspace."
            : lookup === "failed"
              ? "Couldn't load this workspace — reload the page to retry."
              : lookup === "none"
                ? "This workspace has no ecosystem to hold teams yet."
                : "No teams yet.",
      }}
      renderDialog={canCreate ? (onClose, onCreated) => (
        <CreateResourceDialog
          ariaLabel="New team"
          heading="New team"
          blank={teamBlank}
          validate={(d) => teamValidate(d, (teams ?? []).map((t) => t.identifier))}
          create={(d) => {
            // Guarded for safety — the create affordance only renders on a host whose
            // ecosystem can resolve (canCreate), so this rejection covers the narrow
            // window before that resolution completes.
            if (!ecosystemId)
              return Promise.reject(new Error("The workspace hasn't finished loading — try again."));
            return teamsApi.create(
              { displayName: d.displayName.trim(), identifier: d.identifier.trim() },
              ecosystemId,
            );
          }}
          onClose={onClose}
          onCreated={(team) => onCreated(team.id)}
          renderForm={(draft, onChange, error) => (
            <TeamDetail draft={draft} onChange={onChange} error={error} />
          )}
        />
      ) : undefined}
    />
  );
}
