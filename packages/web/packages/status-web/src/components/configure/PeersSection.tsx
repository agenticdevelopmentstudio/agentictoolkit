"use client";

import { useMemo, useState, type ReactElement } from "react";
import { Network } from "lucide-react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Badge } from "@agentic-toolkit/ui/components/badge";
import { Input } from "@agentic-toolkit/ui/components/input";
import { Label } from "@agentic-toolkit/ui/components/label";
import { Switch } from "@agentic-toolkit/ui/components/switch";
import { Field, type TopicLevel } from "@agentic-toolkit/ui/blocks";
import * as api from "../../api/peers";
import type { PeerView, PeerWrite } from "../../api/peers";
import { isValidPeerBaseUrl, normalizePeerBaseUrl } from "../../lib/peer-url";
import { useSettingsEntityLevel } from "../settings-level";
import { useEditorMutations } from "./use-editor-mutations";
import { useDraftForSelection } from "./use-draft-for-selection";
import { EntityEditorShell, SectionErrorText, SectionPlaceholder } from "./section-chrome";

const NO_PEERS: PeerView[] = [];
export const PEERS_QUERY_KEY = ["status-peers"] as const;

interface PeerDraft {
  label: string;
  baseUrl: string;
  isActive: boolean;
  /** A NEW token to send. Blank means "don't touch the stored one" — the secret is
   *  redacted on read, so the field can never be prefilled with the current value. */
  token: string;
  /** Send `token: null` on save, clearing the stored secret (peer reads go public). */
  clearToken: boolean;
}

const blankDraft = (): PeerDraft => ({ label: "", baseUrl: "", isActive: true, token: "", clearToken: false });

/**
 * Admin-only "Fleet peers" section — the ONE place the fleet is configured.
 *
 * A peer is another status monitor this one polls (`/config/peers` → the Fleet view's
 * cards). Configuration lives HERE, in the authenticated backend board, and nowhere
 * else: the public dashboard is a read-only window onto the fleet and must never carry
 * a config surface.
 *
 * The peer token is write-only by design — the backend redacts it from every response —
 * so the editor shows `hasToken` rather than a value: type to set/replace, or flip
 * "Remove token" to clear it. Leaving the field blank leaves the stored secret alone.
 */
export function PeersSection({
  selectedId,
  onNavigate,
}: {
  /** URL-selected peer id (`/settings/peers/<id>`), owned by the board level. */
  selectedId: string | null;
  onNavigate: (id: string | null) => void;
}): ReactElement {
  const queryClient = useQueryClient();
  const { busy, error, setError, run } = useEditorMutations();
  const [creating, setCreating] = useState(false);

  const { data, error: queryError } = useQuery<PeerView[]>({
    queryKey: PEERS_QUERY_KEY,
    queryFn: api.listPeers,
  });
  const peers = data ?? NO_PEERS;

  const current = !creating && selectedId ? (peers.find((p) => p.id === selectedId) ?? null) : null;

  const { draft, setDraft, discardDraft } = useDraftForSelection<PeerView, PeerDraft>({
    selectedId,
    current,
    creating,
    initial: blankDraft,
    load: (p) => ({ label: p.label, baseUrl: p.baseUrl, isActive: p.isActive, token: "", clearToken: false }),
  });

  const trimmedLabel = draft.label.trim();
  const trimmedUrl = normalizePeerBaseUrl(draft.baseUrl);
  const complete = trimmedLabel !== "" && trimmedUrl !== "";
  // Validate what was TYPED, not the normalized form — `isValidPeerBaseUrl` normalizes
  // internally, and applying it twice would diverge from the server the moment
  // normalization stops being idempotent.
  const urlInvalid = trimmedUrl !== "" && !isValidPeerBaseUrl(draft.baseUrl);
  const dirty = creating
    ? trimmedLabel !== "" || trimmedUrl !== ""
    : !!current &&
      (trimmedLabel !== current.label ||
        trimmedUrl !== current.baseUrl ||
        draft.isActive !== current.isActive ||
        draft.token.trim() !== "" ||
        draft.clearToken);

  /** The token field of a write body: a typed value sets it, "Remove token" clears it
   *  (null), and neither leaves the key OFF the patch so the stored secret survives. */
  function tokenField(): { token?: string | null } {
    if (draft.clearToken) return { token: null };
    const typed = draft.token.trim();
    return typed === "" ? {} : { token: typed };
  }

  async function refresh(): Promise<void> {
    // The Fleet view reads the same peers through /api/fleet — invalidate it too, and
    // await BOTH: an operator who saves and immediately switches to Fleet must not be
    // shown the pre-mutation board (a peer they just deleted, or one still missing).
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: PEERS_QUERY_KEY }),
      queryClient.invalidateQueries({ queryKey: ["fleet"] }),
    ]);
  }

  // No `urlInvalid` guard here on purpose: Save is disabled while the URL is invalid
  // (see `canSave`), and the inline message under the field is the ONE place that
  // explains why — a second, unreachable copy of that sentence could only rot.
  function save(): void {
    void run(async () => {
      if (creating) {
        const body: PeerWrite = { label: trimmedLabel, baseUrl: trimmedUrl, isActive: draft.isActive, ...tokenField() };
        const created = await api.createPeer(body);
        await refresh();
        setCreating(false);
        onNavigate(created.id);
      } else if (current) {
        await api.updatePeer(current.id, {
          label: trimmedLabel,
          baseUrl: trimmedUrl,
          isActive: draft.isActive,
          ...tokenField(),
        });
        await refresh();
        // The token inputs are one-shot: clear them so a later save can't re-send them.
        setDraft((d) => ({ ...d, token: "", clearToken: false }));
      }
    });
  }

  function del(): void {
    if (!current) return;
    const id = current.id;
    void run(async () => {
      await api.deletePeer(id);
      await refresh();
      onNavigate(null);
    });
  }

  // Publish the roster as the hierarchy's entity level; the editor is the leaf.
  const level = useMemo<TopicLevel>(
    () => ({
      id: "roster-peers",
      title: "Fleet peers",
      items: peers.map((p) => ({
        id: p.id,
        label: p.label,
        sublabel: `${p.baseUrl}${p.isActive ? "" : " · off"}`,
        icon: <Network size={16} aria-hidden />,
        trailing: p.hasToken ? (
          <Badge variant="neutral" title="A peer token is set" aria-label="authenticated">
            auth
          </Badge>
        ) : undefined,
      })),
      selectedId: creating ? null : selectedId,
      onSelect: (id) => {
        setError(null);
        setCreating(false);
        onNavigate(id);
      },
      onClear: () => {
        setError(null);
        setCreating(false);
        onNavigate(null);
      },
      onNew: () => {
        setError(null);
        setCreating(true);
        discardDraft();
        setDraft(blankDraft());
        onNavigate(null);
      },
      newLabel: "New peer",
      newActive: creating,
      emptyLabel: queryError ? "Failed to load peers." : "No peers yet.",
    }),
    [peers, selectedId, creating, onNavigate, setError, setDraft, discardDraft, queryError],
  );
  useSettingsEntityLevel(level);

  if (queryError instanceof Error) {
    return <SectionErrorText>{queryError.message}</SectionErrorText>;
  }

  if (!creating && !current) {
    return <SectionPlaceholder>Select a peer to edit, or add the monitor you want this one to watch.</SectionPlaceholder>;
  }

  return (
    <EntityEditorShell
      onCancel={() => {
        setError(null);
        setCreating(false);
        discardDraft();
        onNavigate(null);
      }}
      onSave={save}
      canSave={dirty && complete && !urlInvalid && !busy}
      saving={busy}
      onDelete={del}
      canDelete={current !== null}
      deleteConfirm={
        current
          ? {
              title: `Remove peer “${current.label}”?`,
              description: "This monitor stops polling it and its fleet card disappears. The peer itself is untouched.",
            }
          : null
      }
      error={error}
    >
      <div className="flex max-w-md flex-col gap-3 p-4">
        <Field label="Label">
          <Input
            value={draft.label}
            placeholder="e.g. Lewis (testing)"
            onChange={(e) => setDraft((d) => ({ ...d, label: e.target.value }))}
            aria-label="Peer label"
          />
        </Field>
        <Field label="Base URL">
          <Input
            inputMode="url"
            value={draft.baseUrl}
            placeholder="https://status.example.com"
            onChange={(e) => setDraft((d) => ({ ...d, baseUrl: e.target.value }))}
            aria-label="Peer base URL"
          />
        </Field>
        {urlInvalid && <SectionErrorText>Must be an absolute http(s) URL.</SectionErrorText>}
        <Field label="Peer token (blank = leave unchanged; the stored value is never shown)">
          <Input
            type="password"
            autoComplete="off"
            value={draft.token}
            disabled={draft.clearToken}
            placeholder={current?.hasToken ? "•••••••• — type to replace" : "none — this peer's reads are public"}
            onChange={(e) => setDraft((d) => ({ ...d, token: e.target.value }))}
            aria-label="Peer token"
          />
        </Field>
        {current?.hasToken && (
          <Label className="flex items-center gap-2">
            <Switch
              checked={draft.clearToken}
              onCheckedChange={(checked) => setDraft((d) => ({ ...d, clearToken: checked, token: checked ? "" : d.token }))}
            />
            <span className="font-mono text-[0.8rem] text-apt-text-muted">Remove token on save</span>
          </Label>
        )}
        <Label className="flex items-center gap-2">
          <Switch checked={draft.isActive} onCheckedChange={(checked) => setDraft((d) => ({ ...d, isActive: checked }))} />
          <span className="font-mono text-[0.8rem] text-apt-text-muted">Active — poll this peer</span>
        </Label>
      </div>
    </EntityEditorShell>
  );
}
