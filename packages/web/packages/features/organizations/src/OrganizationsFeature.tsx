"use client";

import { useCallback, useMemo } from "react";
import type { ReactElement } from "react";
import { Building2, KeyRound, Server, Settings, UsersRound } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { ResourceExplorer, type ResourceTopic } from "@agentic-toolkit/resource";
import { notifyWorkspacesChanged, useResourceItemPrefetch } from "@agentic-toolkit/data";
import {
  organizationsApi,
  ORGANIZATIONS_QUERY_KEY,
  type Organization,
  type OrganizationListRow,
} from "@agentic-toolkit/data/organizations";
import {
  EcosystemConfigGate,
  ServerBagsPane,
  StorageTokensPanel,
} from "@agentic-toolkit/ecosystem-config";
import { TeamsFeature } from "@agentic-toolkit/teams";
import { parseTeamsPath } from "@agentic-toolkit/teams/parse";
import {
  OrgSettingsGroup,
  ORG_RECORD_CACHE_KEY,
  ORG_SETTINGS_DESCRIPTION,
  type OrgSettingsHrefs,
} from "./OrgSettingsPane";
import { NewOrganizationModal } from "./NewOrganizationModal";
import type { OrganizationsPathSelection } from "./parse-path";

export interface OrganizationsFeatureProps extends OrganizationsPathSelection {
  /** The feature's URL base. The organizations site mounts it at the workspace root (""). */
  basePath: string;
  /** The resolved workspace whose organizations this rail lists. The SLUG scopes the query; the
   *  KIND decides what the list means, and therefore what the rail says it is showing. */
  workspaceSlug: string;
  workspaceKind: "individual" | "organization";
  /** The workspace's display name — the rail names an ORG workspace in its own blurb, because
   *  "the organizations owned by Agentic Developer Studio" is the sentence that stops a row from
   *  looking like a self-reference. */
  workspaceName: string;
  /**
   * The host's help-store lookup, keyed by ROUTE — the keys are spelled at the topic that reads
   * one. Threaded rather than imported because the sentences live in adh's vocabulary tier, which
   * a portable package may not reach (see `@agentic-toolkit/adh/help/store`).
   */
  helpFor?: (key: string) => string | undefined;
}

/**
 * The Organizations feature: the caller's organizations as the root list, and each org's
 * Server bags / Tokens / Teams / Settings beside it.
 *
 * The list is WORKSPACE-SCOPED: `organizationsApi.list(workspaceSlug)`, and what it returns
 * depends on the workspace you are standing in —
 *
 *   - a PERSONAL workspace lists the orgs you OWN plus the orgs you BELONG TO;
 *   - an ORG workspace lists the orgs THAT ORG owns.
 *
 * It did not always. The rail used to read `workspacesApi.list()` filtered to organizations,
 * which asks a pure MEMBERSHIP question — the same answer under every workspace. So switching
 * workspaces changed the chrome and nothing else, and the org you had just switched INTO sat in
 * its own organizations list looking like it contained itself. The fix was not a filter: orgs had
 * no owning workspace to filter BY. They carry one now (`owner_kind`/`owner_id`, the pair personas
 * have always had), and this reads it. `workspacesApi.list()` is still exactly right for the
 * workspace SWITCHER above, which really is asking "where can I go".
 *
 * The topics deliberately reuse the hub's own words rather than inventing a second vocabulary for
 * the same things — an org is one entity with one set of knobs, and a user who learns it in one
 * place should not have to relearn it in the other.
 *
 * They are the org's OWN knobs and nothing else. Auth, Feature flags and Sign-in apps are
 * configured per PRODUCT — they say how one product's customers sign in and what it has switched
 * on — so they live on the product rail (`@agentic-toolkit/adh-products`), not here; an org that
 * showed them would be claiming to own settings that belong to each product under it.
 *
 * Billing left for a different reason, and NOT because some other rail configures it: it is
 * unbuilt everywhere. This package's `BillingPane` and the hub's own `billing` feature both render
 * "Coming soon", so the row answered nothing — and with the group gone, nothing mounts
 * `BillingPane` at all. Whoever builds billing decides then whether an ORG is what gets billed.
 *
 * Membership is not a topic either: who is in the org is answered by its Teams, which group its
 * people and the permissions they share. (`MembersPanel` stays exported — the hub still mounts it
 * on its workspace rail.)
 */
export function OrganizationsFeature({
  basePath,
  workspaceSlug,
  workspaceKind,
  workspaceName,
  helpFor,
  all,
  activeOrgSlug,
  activeTopic,
  topicPath,
}: OrganizationsFeatureProps): ReactElement {
  const orgsQuery = useQuery({
    // Keyed BY WORKSPACE, because the answer differs per workspace — a single shared key would
    // serve the previous workspace's rows for one frame after every switch, which is the same
    // wrong-list-for-this-workspace bug in a shorter-lived form.
    queryKey: [...ORGANIZATIONS_QUERY_KEY, workspaceSlug],
    queryFn: () => organizationsApi.list(workspaceSlug),
  });
  // `null` (not `[]`) while loading: ResourceExplorer reads an empty array as a LOADED empty list
  // and falls back to the "All" landing, so a slug in the URL would look deleted for one frame.
  const organizations: OrganizationListRow[] | null = orgsQuery.data ?? null;

  // WHAT THE RAIL SAYS IT IS SHOWING. The list means two different things, so one sentence cannot
  // describe both — and the wrong sentence is what made an org appearing under its own workspace
  // read as a bug. Under an ORG the blurb NAMES the org, so "Agentic Developer Studio" in the row
  // and "owned by Agentic Developer Studio" in the blurb are visibly a parent and a child, not a
  // thing containing itself.
  const isOrgWorkspace = workspaceKind === "organization";
  const railHelp = isOrgWorkspace
    ? `The organizations ${workspaceName} owns. Pick one to manage its config values, tokens, teams and record — or create another one under ${workspaceName}.`
    : "The organizations you own or belong to. Pick one to manage its config values, tokens, teams and record — or create a new one.";
  const railEmptyLabel = isOrgWorkspace
    ? `${workspaceName} doesn't own any organizations yet.`
    : "You aren't in any organizations yet.";

  // Warm the org's own RECORD as the pointer rests on its row, onto the entry Settings ▸ Profile
  // reads. The explorer already warms the ROUTE; the record is the other half of that click, and
  // warming one half only makes the click as fast as its slower half. The id here is the slug —
  // `getId` below says so — which is exactly what `organizationsApi.resolve` takes and what the
  // Settings group caches under. The key is the group's own constant, not a matching literal.
  const prefetchOrg = useResourceItemPrefetch<Organization>(
    ORG_RECORD_CACHE_KEY,
    organizationsApi.resolve,
  );

  // Keyed on `refetch`, not on the query object: react-query hands back a NEW result object every
  // render, so depending on it would rebuild this callback every render while looking stable —
  // and every memo'd child and effect downstream would re-run with it. `refetch` is stable.
  const reload = useCallback(async () => {
    await orgsQuery.refetch();
    // This list is not the only one a created or archived org changes: an org IS a workspace, so
    // the switcher, the header's workspaces flyout and every chooser reading the workspace list
    // are stale the moment this row appears. Refetching here reached none of them — the hub's list
    // lives in the HOST's react-query client, a different physical copy of the library that no
    // hook in this package can address. `notifyWorkspacesChanged` is the announcement that
    // crosses; see its docstring for the three caches involved.
    notifyWorkspacesChanged();
  }, [orgsQuery.refetch]);

  // Where a rename or an archive lands the browser, expressed in THIS host's URL space. Both are
  // full reloads rather than router pushes: a rename moves the org's segment out from under the
  // component doing the navigating, and an archive removes the row the whole stack is addressed by.
  const settingsHrefs: OrgSettingsHrefs = useMemo(
    () => ({
      renamed: (newSlug: string) => `${basePath}/${newSlug}/settings`,
      // The list landing — the one URL here that stays valid once this org is gone.
      archived: `${basePath}/all`,
    }),
    [basePath],
  );

  const topics: ResourceTopic[] = [
    // The two ecosystem-scoped topics, lifted out of the Configuration group that used to hold
    // them as rows. Both are FLAT — one pane, nothing below them — so once the other four rows
    // left as product settings (see above), the group was a disclosure level over two leaves.
    //
    // Each goes through the gate itself rather than this component resolving the ecosystem once
    // above the rail: only the chosen topic is ever mounted, so a resolution up here would also
    // run for Teams and Settings, which have no ecosystem in them.
    {
      id: "server-bags",
      label: "Server bags",
      icon: <Server size={16} aria-hidden />,
      description: "Arbitrary key → JSON config values, read at runtime by what the organization runs.",
      leadsTo: "detail",
      render: (scopedId) => (
        <EcosystemConfigGate workspaceSlug={scopedId} feature="Server bags">
          {(ecosystemId) => (
            <ServerBagsPane ecosystemId={ecosystemId} help={helpFor?.("ecosystems/server-bags")} />
          )}
        </EcosystemConfigGate>
      ),
    },
    {
      id: "tokens",
      label: "Tokens",
      icon: <KeyRound size={16} aria-hidden />,
      description: "Storage-access tokens, each with its own isolated bucket. Mint, list and revoke them here.",
      leadsTo: "detail",
      // `workspace` is what makes these the ORG'S tokens rather than the signed-in user's: it pins
      // every list/mint/revoke to the workspace's owning principal (see StorageTokensPanel).
      render: (scopedId) => (
        <EcosystemConfigGate workspaceSlug={scopedId} feature="Tokens">
          {(ecosystemId) => <StorageTokensPanel ecosystemId={ecosystemId} workspace={scopedId} />}
        </EcosystemConfigGate>
      ),
    },
    {
      id: "teams",
      label: "Teams",
      icon: <UsersRound size={16} aria-hidden />,
      description: "Teams group people and the permissions they share. Pick a team to manage it.",
      leadsTo: "list",
      // Teams is a whole nested FEATURE, not a pane: it owns a four-segment grammar of its own
      // below this topic. So it gets the raw `topicPath` and re-parses it, and routes off its own
      // `basePath` — which is why the org grammar hands topics their remaining segments rather
      // than a single leaf id (see parse-path). `leaf` is ignored here on purpose: it reaches one
      // segment deep, and Teams needs four.
      render: (scopedId) => (
        <TeamsFeature
          basePath={`${basePath}/${scopedId}/teams`}
          workspaceSlug={scopedId}
          {...parseTeamsPath(topicPath)}
        />
      ),
    },
    {
      id: "settings",
      label: "Settings",
      icon: <Settings size={16} aria-hidden />,
      description: ORG_SETTINGS_DESCRIPTION,
      // Four rows of its own (Social links / Addresses / Usage / Settings), so it
      // publishes a list.
      leadsTo: "list",
      render: (scopedId, _titleFor, leaf) => (
        <OrgSettingsGroup slug={scopedId} hrefs={settingsHrefs} leaf={leaf} />
      ),
    },
  ];

  return (
    <ResourceExplorer<OrganizationListRow>
      basePath={basePath}
      all={all}
      activeId={activeOrgSlug}
      activeTopic={activeTopic}
      // ResourceExplorer's own 4th segment — Settings' open row. Topics that route themselves
      // (Teams) read `topicPath` instead, and the two flat panes have nothing below them; this
      // keeps the stack's breadcrumb and leaf selection honest for the one that does.
      // `activeMemberEntityId` (the 5th) is deliberately not passed: it only fed a GROUPING
      // topic's inner entity, and this rail no longer has one.
      activeLeafId={topicPath[0]}
      items={organizations}
      // The SLUG is the id: it is what identifies an org everywhere on the platform, what
      // `?workspace=` takes, and what every one of these topics scopes by. There is no separate
      // org id in a URL.
      getId={(w) => w.slug}
      prefetchItem={prefetchOrg}
      getLabel={(w) => w.name}
      itemIcon={<Building2 size={16} aria-hidden />}
      nameSuffix="Organization"
      topics={topics}
      rail={{
        title: "Organizations",
        help: railHelp,
        emptyLabel: railEmptyLabel,
        // The slug, not the display name, is the unique key — two orgs may share a name, and
        // the slug is what every URL, invite link and API path carries. Without it beside the
        // name the rail can show two rows a user cannot tell apart.
        getSublabel: (w) => w.slug,
      }}
      newLabel="New Organization"
      // `open` is a constant here because ResourceExplorer MOUNTS the dialog only while it is
      // open; the modal keeps the prop because the hub's workspace bar renders it persistently.
      renderDialog={(onClose, onCreated) => (
        <NewOrganizationModal
          open
          // The rail's own workspace: a "New Organization" started from an org workspace creates
          // an org THAT ORG owns, which is what makes the new row appear in the very list the
          // button sits on. Passing the wrong slug here would file the org somewhere the user
          // cannot see it.
          workspaceSlug={workspaceSlug}
          onClose={onClose}
          onCreated={onCreated}
        />
      )}
      reload={reload}
    />
  );
}
