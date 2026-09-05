// Fleet-peer client. Talks to the status BACKEND's admin CRUD via the same
// `/[...path]` proxy as the rest of the config surface: `/config/peers` →
// `BACKEND_URL/config/peers` (admin-gated there, so this is an admin-only surface).
// The base path itself is the caller's `StatusApiClient` — this module never
// names `/api`.
//
// A peer is another status monitor this one polls: the fleet is exactly the set of
// rows here plus this monitor itself. This is the ONLY place the fleet is configured —
// the public wallboard has no config surface at all.

import type { StatusApiClient } from "./client";

const PEERS = "/config/peers";

/**
 * A peer as the backend returns it. The `token` column is a fleet shared secret and is
 * redacted server-side on every read, so what comes back is `hasToken` — WHETHER one is
 * set. That distinction is the reason the flag exists: an always-blank token field can't
 * tell "this peer's reads are public" from "a token is set but hidden".
 */
export interface PeerView {
  id: string;
  label: string;
  baseUrl: string;
  isActive: boolean;
  hasToken: boolean;
}

/** The writable fields. `token`: a string sets/replaces it, `null` clears it, and
 *  OMITTING it on a patch leaves the stored secret untouched (it can't be echoed back,
 *  so "unchanged" has to be expressible as absence). */
export interface PeerWrite {
  label: string;
  baseUrl: string;
  token?: string | null;
  isActive: boolean;
}

export function listPeers(api: StatusApiClient): Promise<PeerView[]> {
  return api.json<PeerView[]>(PEERS);
}

export function createPeer(api: StatusApiClient, body: PeerWrite): Promise<PeerView> {
  return api.json<PeerView>(PEERS, { method: "POST", body: JSON.stringify(body) });
}

export function updatePeer(api: StatusApiClient, id: string, body: Partial<PeerWrite>): Promise<PeerView> {
  return api.json<PeerView>(`${PEERS}/${id}`, { method: "PATCH", body: JSON.stringify(body) });
}

export function deletePeer(api: StatusApiClient, id: string): Promise<void> {
  return api.json<void>(`${PEERS}/${id}`, { method: "DELETE" });
}
