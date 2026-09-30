"use client";

import { useEffect, type ReactNode } from "react";
import type { TopicLeaf } from "@agentic-toolkit/resource";
import { ApplicationsPane, type RenderTransferSection } from "@agentic-toolkit/adh-ecosystem-panes";

/** Old ids in the Applications segment that named no application: `settings` (the list's
 *  Settings row, the ecosystem's client auth — Users ▸ Authentication now), `signin-apps`
 *  (Client Auth, whose sign-in clients became each application's own login registration) and
 *  `auth` (Users ▸ Settings, once sent on to that Settings row). Their links land on the list. */
const OLD_LIST_IDS: ReadonlySet<string> = new Set(["settings", "signin-apps", "auth"]);

/** The old Applications MEMBER id: for a while the row was a group of two members, Applications
 *  and Settings, so an application's address was `…/applications/apps/<appId>`. */
const OLD_APPS_MEMBER = "apps";

/** The old row below an application: for a while opening an app showed a one-row level, Settings,
 *  at `…/applications/<appId>/settings`. Opening the app is its settings now. */
const OLD_APP_SETTINGS = "settings";

/**
 * The Applications row: ONE list — the product's applications. Mike, 2026-09-29: the row must not
 * open onto a second list holding an "Applications" entry. Opening an application opens
 * everything about it — name, id, grants, tokens and its own login registration — at
 * `…/applications/<appId>`; nothing sits below it. The ecosystem's sign-in settings are not here:
 * they are Users ▸ Authentication (Mike, 2026-09-30).
 *
 * Host-owned like GamingGroup, because `@agentic-toolkit/ecosystems`'s in-package groups compose
 * only panes that package can name, and Applications is adh's.
 *
 * An application is `…/applications/<appId>`. The old addresses are sent on (replace, not
 * push, so Back still leaves): `settings` / `signin-apps` / `auth` to the list, and
 * `apps/<appId>` and `<appId>/settings` to `<appId>`.
 */
export function ApplicationsGroup({
  ecosystemId,
  title,
  leaf,
  subLeafFor,
  helpFor,
  renderTransfer,
}: {
  ecosystemId?: string;
  /** The row's scoped title ("Applications" for this product). */
  title?: ReactNode;
  /** Which application is open — the row's own URL segment. */
  leaf?: TopicLeaf;
  /** The segment below this one — read only to forward an old `apps/<appId>` or
   *  `<appId>/settings` link. */
  subLeafFor?: (memberId: string) => TopicLeaf;
  helpFor: (key: string | undefined) => string | undefined;
  renderTransfer?: RenderTransferSection;
}) {
  const leafId = leaf?.leafId ?? null;
  const oldListId = leafId !== null && OLD_LIST_IDS.has(leafId);
  const oldAppsMember = leafId === OLD_APPS_MEMBER;
  const oldAppId = oldAppsMember && subLeafFor ? subLeafFor(OLD_APPS_MEMBER).leafId : null;
  const appId = leafId !== null && !oldListId && !oldAppsMember ? leafId : null;
  const oldAppSettings = appId !== null && subLeafFor?.(appId).leafId === OLD_APP_SETTINGS;
  useEffect(() => {
    if (oldListId) leaf?.onSelect(null, { replace: true });
    else if (oldAppsMember) leaf?.onSelect(oldAppId, { replace: true });
    else if (oldAppSettings) leaf?.onSelect(appId, { replace: true });
  }, [oldListId, oldAppsMember, oldAppId, oldAppSettings, appId, leaf]);

  const redirecting = oldListId || oldAppsMember;
  return (
    <ApplicationsPane
      ecosystemId={ecosystemId}
      title={title}
      help={helpFor("ecosystems/applications")}
      leaf={leaf && redirecting ? { ...leaf, leafId: oldAppId } : leaf}
      renderTransfer={renderTransfer}
    />
  );
}
