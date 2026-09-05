'use client';

import * as React from 'react';

import { ShiprConsole } from './ShiprConsole';
import { createShiprClient, type Fetcher } from './client';
import type { ForgeConnection } from './types';

/**
 * The console, wired to ONE workspace — everything a host needs to mount shipr except the
 * two things only a host knows: how to authenticate a request, and which workspace this is.
 *
 * It lives here rather than in the site because it is shipr's UI, not the site's. The site's
 * copy of this was ~100 lines naming the client, its memoisation, and the credential list the
 * register wizard consumes — three shipr concepts a host cannot get right without reading this
 * package, and three the next host to mount the console would have to re-derive. A site owns
 * its address and its chrome; shipr owns what fills them.
 *
 * A component rather than JSX a host writes, because it holds two things across renders: the
 * client (rebuilding it every render would hand the console a new object identity and re-trigger
 * every effect keyed on it) and the caller's forge connections.
 *
 * This does NOT move the boundary {@link ShiprConsole} draws. The console still takes its
 * connections as a prop and never reads `/integrations` itself, because which credentials exist
 * is a question about the PERSON, not about this workspace's deployment tree. The reading is
 * done here, one level out — which is exactly the "host" that docblock names. A host with a
 * different answer mounts the console directly and passes its own.
 */
export interface ShiprHomeProps {
  /** A `fetch` that already carries auth — `authedFetch` on a fleet site. Supplied rather
   *  than imported so this package stays independent of how a host signs a request; see
   *  {@link Fetcher}. */
  fetcher: Fetcher;
  workspaceSlug: string;
  /** Breadcrumb root — the workspace's NAME, which is what an operator calls it. The slug is
   *  an address, and an address is not a label. */
  rootLabel?: string;
  /** A shell hands the console a column to fill, and the default fills it: one view of rail
   *  plus detail, with no second pane beside it to leave a gap when it is short. */
  className?: string;
}

export function ShiprHome({
  fetcher,
  workspaceSlug,
  rootLabel,
  className = 'min-h-0 flex-1',
}: ShiprHomeProps): React.ReactElement {
  const client = React.useMemo(
    () => createShiprClient(fetcher, workspaceSlug),
    [fetcher, workspaceSlug],
  );

  // Left undefined until the first read LANDS, so the wizard can tell a list it is still
  // waiting for from one it has and that is empty. Those are different sentences.
  const [connections, setConnections] = React.useState<ForgeConnection[]>();
  /**
   * Why there is no list, when the reason is a failure rather than an absence.
   *
   * Held rather than dropped. A swallowed error left the wizard three situations — not read
   * yet, read and empty, could not be read — wearing one sentence, "No GitHub App
   * installation", which is a guess in two of the three cases and wrong in one. Nothing here
   * throws and nothing blocks on it: a credential list that cannot be read must still not
   * stand between the operator and a status run.
   */
  const [connectionsError, setConnectionsError] = React.useState<string | null>(null);

  // RE-READABLE, because the console can change this list. Connecting a GitHub account happens
  // in the Configure dialog's Connections dialog, two dialogs away from the wizard that consumes
  // the result; a list read once at mount would still be empty in the wizard the operator opens
  // ten seconds later, and the only cure would be a page reload. So this is a named function the
  // console can call, not an effect body.
  const refreshConnections = React.useCallback(() => {
    let live = true;
    client
      .connections()
      .then((res) => {
        if (!live) return;
        setConnections(res.connections);
        setConnectionsError(null);
      })
      .catch((e: Error) => {
        // `connections` is deliberately left alone: a refresh that fails after a good read
        // should leave the good list on screen with a note beside it, not replace it with an
        // empty box. The wizard reads the error first only when it has nothing to show.
        if (live) setConnectionsError(e.message);
      });
    return () => {
      live = false;
    };
  }, [client]);

  React.useEffect(() => refreshConnections(), [refreshConnections]);

  return (
    <ShiprConsole
      client={client}
      connections={connections}
      connectionsError={connectionsError}
      onConnectionsChanged={refreshConnections}
      rootLabel={rootLabel}
      className={className}
    />
  );
}
