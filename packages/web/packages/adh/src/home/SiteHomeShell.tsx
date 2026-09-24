'use client'

import { useCallback, type ReactElement } from 'react'
import { usePathname } from 'next/navigation'
import { TopicSelectHint } from '@agenticdevelopertoolkit/ui/blocks'
import { useResourceList, workspacesApi, type Workspace } from '@agentic-toolkit/data'
import { HomeBarHost } from '@agentic-toolkit/resource'
import { ProfileFallback } from '../profile/ProfileFallback'
import { useSiteIdOrNull } from '@agentic-toolkit/adh/site/site-id'
import { WorkspaceBar } from './WorkspaceBar'
import { useWorkspaceRoute } from './useWorkspaceRoute'
import { workspacePathTail } from './workspacePathTail'
import type { SiteHomeShellProps } from './SiteHomeModel'

// Module scope, so its identity is stable: useResourceList takes `load` as a fetch dependency and
// a new identity each render would loop.
const loadWorkspaces = (): Promise<Workspace[]> => workspacesApi.list()

/**
 * The shared shell for a feature site's workspace route: one workspace chooser in a bar
 * directly under the header, and below it that site's own HTDV scoped to the chosen workspace.
 *
 * The DEFAULT, not the only one: a site may declare `shell` on its model and get its own. One
 * does — see SiteHomeModel.shell for which and why. Everything this file defends is owed by a
 * replacement too, so read the reasons below before writing one.
 *
 * Every site that scopes to a workspace used to grow its own chooser inside its HTDV stack —
 * eating the widest column, reimplemented per feature package, and the answer did not travel.
 * This owns all of it once:
 *
 *   - The ONE workspacesApi.list() fetch. The bar and the resolution read it.
 *   - Resolution, the URL-as-truth replace, and persistence of an explicit choice — all of it
 *     useWorkspaceRoute's, which the hub mounts too (it needs a different LIST — the fetch on the
 *     line above drops teams — but the behaviour behind its switcher is the same one).
 *   - A workspace this caller cannot reach: a settled list without the URL's slug renders that
 *     slug's PROFILE (`ProfileFallback`) rather than the workspace. See the check below the hook
 *     for the three states that are NOT that.
 *   - Holding `children` until resolution, so no feature mounts unscoped and fires a list
 *     request the backend would answer with the wrong reach. `children` is a FUNCTION for that
 *     reason: a node would be CONSTRUCTED on every render, including the ones before a workspace
 *     exists, so its props could only be built from the raw URL segment — which is `undefined`
 *     at `/home` and stale mid-redirect. Called instead, it runs once the answer is known and is
 *     handed that answer.
 *   - Rendering the chooser ONCE, in a bar directly under the header, at every width.
 *
 * Signed-out visitors DO reach here: the workspace route's gate is `WorkspaceOrProfileGate`,
 * which renders `children` (this shell) for a caller with a session and the principal's profile
 * for one without. This shell makes the narrower judgement — authenticated, but not a MEMBER of
 * this workspace — and lands in the same place.
 */
export function SiteHomeShell({
  workspaceSlug,
  workspaceHref,
  children,
}: SiteHomeShellProps): ReactElement {
  // `error` is not optional to read here. A failed list leaves `items` at its previous value —
  // null on a cold mount (use-resource-list only calls setError on the catch path) — and a null
  // list is indistinguishable from a list still loading: resolution stays `undefined` forever, so
  // the children never mount, the empty-state hint never fires, and the page sits blank behind a
  // chooser with nothing in it. Every one of the 38 sites' gated surface has that same failure, so
  // the shell owns saying so.
  //
  // The cache key is a bare literal, and can be: it identifies a REQUEST, not a mount point, and
  // there is one workspace list per signed-in caller across the whole family. It used to be keyed
  // on the shell's base so two mounts at different bases could not read each other's rows — a
  // distinction that never existed, since both would have fetched the same list.
  const { items: workspaces, error, isFetching } = useResourceList<Workspace>(
    'workspaces',
    loadWorkspaces,
  )
  // Memoized because useWorkspaceRoute holds this in two effects' dependency arrays — a fresh
  // closure each render would re-run both on every render. `workspaceHref` is the host's own
  // answer for where its gated surface lives (see SiteHomeShellProps); absent, a workspace lives
  // at its bare slug, which is 38 of the 39 sites.
  const hrefFor = useCallback(
    (slug: string) => workspaceHref?.(slug) ?? `/${slug}`,
    [workspaceHref],
  )
  // Switching workspace KEEPS what you were looking at: the segments below the workspace are this
  // site's own selected path (`model.parse` reads exactly these — see SiteHomeRoute), so moving
  // them onto the new workspace is what makes the HTDV land on the same place rather than back at
  // the site's root.
  //
  // Carried WHOLE and unvalidated, which is the honest answer here rather than a shortcut. Below
  // the workspace a feature site's segments are entity ids, and whether one exists in the
  // destination is a question only that workspace's own list can answer — a round trip this bar
  // has not made and should not make to service a click. It does not need to: every deep-linkable
  // pane on the platform already resolves its id against the rows it loads and treats an unknown
  // one as "nothing open", showing the list instead (ServicesSection, PersonasSection,
  // StackGroupDetail all say so in as many words). So an id the destination does not have settles
  // by itself onto the parent level — which IS the fallback this feature is specified to have —
  // and one it does have (the user-scoped lists, where the row is the same row) stays selected.
  const pathname = usePathname() ?? ''
  const switchHrefFor = useCallback(
    (slug: string) => `/${[slug, ...workspacePathTail(pathname)].join('/')}`,
    [pathname],
  )
  // No `canPersist`: every row this list carries is an owner-scopable workspace (workspacesApi
  // drops teams), so any of them is legitimate cross-site preference material.
  const { resolved, onSelect } = useWorkspaceRoute({
    workspaces,
    workspaceSlug,
    hrefFor,
    switchHrefFor,
  })
  // The resolved workspace's own row, for the scope below (see SiteHomeScope.workspace). `resolved`
  // can only ever BE a member of this list — useWorkspaceRoute resolves through its `known()`
  // check, which rejects any slug the list does not carry, and otherwise falls back to the list's
  // own first row — so this lookup is total wherever the guard below has already passed. Written as
  // a lookup rather than an assertion so a future change to that resolution cannot turn a wrong
  // slug into a wrong ROW: a miss holds `children` exactly as an unresolved slug does, which is a
  // state this shell already renders (the bar, and nothing under it).
  const workspace = workspaces?.find((w) => w.slug === resolved) ?? null
  const siteId = useSiteIdOrNull()

  // The URL names a slug the caller is not a member of → their PROFILE, not a 404.
  //
  // This used to be `notFound()`, and the change is the point of the feature rather than a
  // softening of it: `/<slug>` is one address serving two things, and which one a visitor gets
  // is decided by what they can reach. A caller who cannot open the workspace is, by
  // elimination, looking at somebody's page — the hub's own gate has encoded that idea since it
  // was written, and merely encoded it at the wrong address (`router.replace('/user/<slug>')`).
  //
  // Every rung of the four-part condition below still earns its place, and for the SAME reasons
  // it did when the answer was a refusal: a wrong profile is as wrong as a wrong 404.
  //   - still loading — `workspaces` is null, so this is false and the page holds.
  //   - the list FAILED — `useResourceList` leaves `items` at null on a cold miss, so this is
  //     false again and the error hint below renders. A retryable failure must not become a
  //     profile page any more than it may become a permanent-looking 404.
  //   - no slug at all (`/home`) — nothing to refuse and nobody to show.
  //   - `!isFetching` — the module cache can seed a list that predates a workspace created
  //     since, and a seeded first render is EXACTLY the render on which a brand-new slug is
  //     absent. Showing the owner a PROFILE of their own new workspace would be a worse
  //     misfire than the 404 was.
  if (
    workspaceSlug !== undefined &&
    workspaces !== null &&
    !isFetching &&
    !workspaces.some((w) => w.slug === workspaceSlug)
  ) {
    // Reaching here without a provider is a wiring bug in the route, not a state to render: this
    // branch only fires when the URL named a workspace, which is the `[workspace]` layout's
    // subtree, which is where SiteIdProvider is mounted. `/home` — the mount that has no provider
    // — cannot get here at all, because `workspaceSlug` is undefined there.
    if (siteId === null) {
      throw new Error(
        'SiteHomeShell reached the profile branch outside <SiteIdProvider> — the workspace layout must mount it',
      )
    }
    return <ProfileFallback slug={workspaceSlug} siteId={siteId} />
  }

  return (
    <>
      <WorkspaceBar
        workspaces={workspaces}
        selected={resolved ?? null}
        onSelect={onSelect}
      />
      {/* The home bar hosts every page-level control this site has — its search, its filters, its
          primary "Add" — in the strip between this bar and the breadcrumb bar below. It is mounted
          UNCONDITIONALLY and draws nothing until a feature claims it, so the ~24 sites that publish
          no controls are pixel-identical to before. It wraps `children` rather than sitting beside
          it because the feature that publishes into it is inside `children`. */}
      <HomeBarHost>
        {/* Said only while the list is genuinely missing: a reload that fails AFTER a successful one
            leaves the workspaces on screen, and replacing a working page with an error would be a
            worse answer than the slightly stale one it already has. */}
        {error !== null && workspaces === null && (
          <TopicSelectHint title="Couldn't load your workspaces. Reload the page to try again." />
        )}
        {/* No error clause needed here, and one would be wrong: `resolved` is `null` only once the
            list has ARRIVED and was empty (it stays `undefined` while `workspaces` is null), so a
            failed request cannot reach this line. The one state that could — a successful empty list
            followed by a failed refetch — is still a user with no workspaces, and saying so beats
            replacing a true statement with an apology. */}
        {resolved === null && (
          <TopicSelectHint title="No workspaces yet — create one from the hub to get started." />
        )}
        {/* `resolved === workspaceSlug` is what narrows `resolved` to the settled string: it is
            `undefined` while resolving and `null` when there is nothing to resolve to, and neither
            equals a slug. So the scope below is built from the RESOLVED workspace — the URL segment
            merely has to agree before anything mounts. */}
        {resolved !== undefined &&
          resolved !== null &&
          resolved === workspaceSlug &&
          workspace !== null &&
          children({
            workspaceSlug: resolved,
            scopedBase: `/${resolved}`,
            workspace,
          })}
      </HomeBarHost>
    </>
  )
}
