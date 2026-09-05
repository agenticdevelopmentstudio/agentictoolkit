"use client";

import { useCallback, useEffect, useRef, useState, type ReactElement } from "react";
import { Plug, RefreshCw } from "lucide-react";

import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";
import { List, ListItem } from "@agenticdevelopertoolkit/ui/components/list";
import { Badge, type badgeVariants } from "@agenticdevelopertoolkit/ui/components/badge";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import type { VariantProps } from "class-variance-authority";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Disclosure } from "@agenticdevelopertoolkit/ui/components/disclosure";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  integrationsApi,
  type MaskedProviderConfig,
  type ProviderCatalogEntry,
  type SafeConnection,
} from "@agentic-toolkit/data/integrations";
import { isServiceUnavailable, errMsg, useResourceList } from "@agentic-toolkit/data";
import { DetailSection } from "@agentic-toolkit/resource";
import { useReportSettingsDirty } from "@agentic-toolkit/resource";
import { ConnectAccountDialog } from "./ConnectAccountDialog";
import { AudienceSyncSettings } from "./AudienceSyncSettings";

type BadgeVariant = NonNullable<VariantProps<typeof badgeVariants>["variant"]>;

const STATUS_VARIANT: Record<string, BadgeVariant> = {
  active: "success",
  pending: "blue",
  error: "error",
  revoked: "orange",
};

function statusVariant(status: string): BadgeVariant {
  return STATUS_VARIANT[status] ?? "neutral";
}

function formatSync(lastSyncAt: string | null | undefined): string {
  if (!lastSyncAt) return "Never synced";
  const d = new Date(lastSyncAt);
  return Number.isNaN(d.getTime()) ? "Never synced" : `Last synced ${d.toLocaleString()}`;
}

/** The connection's stored syncSettings as a plain object ({} when unset/garbage). */
function settingsOf(c: SafeConnection): Record<string, unknown> {
  const s = (c as { syncSettings?: unknown }).syncSettings;
  return s && typeof s === "object" ? (s as Record<string, unknown>) : {};
}

/** The string members of a stored settings array (tolerates non-array garbage). */
function strArray(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((s): s is string => typeof s === "string") : [];
}

/** Props for a per-provider sync-settings form: the connection + its STORED settings,
 *  so the form prefills instead of blind-overwriting (the backend PATCH replaces the
 *  whole syncSettings jsonb — a blank re-save would otherwise wipe saved values). */
interface SyncSettingsFormProps {
  connectionId: string;
  initial: Record<string, unknown>;
}

/** Why `windowDays` isn't submittable as-is, or null (blank keeps the default; otherwise a whole
 *  1–366). This IS GmailSyncSettings.onSave's check — onSave calls it and sets what it returns —
 *  so Save disables for exactly the input onSave would reject, and the reason shown beside the
 *  disabled button is word-for-word the error the click would have produced. Gating without
 *  showing this would leave an out-of-range window looking like a broken button. */
function gmailWindowBlockedReason(windowDays: string): string | null {
  const raw = windowDays.trim();
  if (!raw) return null;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 1 || n > 366) {
    return "Window must be a whole number of days between 1 and 366.";
  }
  return null;
}

/** Gmail-only per-connection sync settings (label ids + history window). */
function GmailSyncSettings({ connectionId, initial }: SyncSettingsFormProps) {
  const [labels, setLabels] = useState(() => strArray(initial.gmailLabelIds).join(", "));
  const [windowDays, setWindowDays] = useState(() =>
    typeof initial.gmailWindowDays === "number" ? String(initial.gmailWindowDays) : "",
  );
  // The stored baseline this form was prefilled from — re-set to the just-saved input on a
  // successful save, so Save goes disabled again until the next edit rather than staying
  // clickable for a no-op re-save of what's already persisted.
  const [baselineLabels, setBaselineLabels] = useState(labels);
  const [baselineWindowDays, setBaselineWindowDays] = useState(windowDays);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  const dirty = labels !== baselineLabels || windowDays !== baselineWindowDays;
  const blockedReason = gmailWindowBlockedReason(windowDays);
  const canSave = dirty && blockedReason === null;

  // This form PATCHes straight through — it is nowhere in IntegrationsPane's form state, so
  // nothing else knows the draft exists. Reported on `dirty`, deliberately NOT on `canSave`: an
  // edit Save currently refuses is still work the user would lose. Keyed per connection — one
  // form renders per connected account.
  useReportSettingsDirty(`integration-sync-gmail-${connectionId}`, dirty);

  const labelsId = `gmail-labels-${connectionId}`;
  const windowId = `gmail-window-${connectionId}`;

  async function onSave() {
    const gmailLabelIds = labels
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    const block = gmailWindowBlockedReason(windowDays);
    if (block) {
      setError(block);
      return;
    }
    const raw = windowDays.trim();
    const gmailWindowDays = raw ? Number(raw) : undefined;
    setBusy(true);
    setError(null);
    setSaved(false);
    try {
      // The PATCH replaces the whole syncSettings jsonb, and the form is prefilled from
      // the stored values — so the form state IS the full intended settings: a key the
      // user cleared is omitted (= reset to the worker's default).
      await integrationsApi.patchSettings(connectionId, {
        ...(gmailLabelIds.length ? { gmailLabelIds } : {}),
        ...(gmailWindowDays !== undefined ? { gmailWindowDays } : {}),
      });
      if (alive.current) {
        setSaved(true);
        setBaselineLabels(labels);
        setBaselineWindowDays(windowDays);
      }
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "integration-connections", step: "gmail-settings" });
      if (alive.current) setError(errMsg(err, "Couldn't save sync settings."));
    } finally {
      if (alive.current) setBusy(false);
    }
  }

  return (
    <form
      className="flex flex-col gap-3 pt-1"
      onSubmit={(e) => {
        e.preventDefault();
        void onSave();
      }}
    >
      <div className="flex flex-col gap-2">
        <Label htmlFor={labelsId}>Label ids</Label>
        <Input
          id={labelsId}
          value={labels}
          placeholder="INBOX, IMPORTANT"
          onChange={(e) => {
            setLabels(e.target.value);
            setSaved(false);
          }}
        />
        <p className="text-xs text-apt-text-muted">Comma-separated. Leave blank to keep INBOX.</p>
      </div>
      <div className="flex flex-col gap-2">
        <Label htmlFor={windowId}>History window (days)</Label>
        <Input
          id={windowId}
          type="number"
          min={1}
          max={366}
          value={windowDays}
          placeholder="30"
          onChange={(e) => {
            setWindowDays(e.target.value);
            setSaved(false);
          }}
        />
        <p className="text-xs text-apt-text-muted">Between 1 and 366. Leave blank to keep the default.</p>
      </div>
      <ErrorText error={error} />
      {/* Why Save is grey. `canSave` disables the button, so onSave's own range check can no
          longer be reached by clicking; without this an out-of-range window reads as a broken
          button. Gated on `dirty` — a stored value the user hasn't touched isn't their problem. */}
      {!error && blockedReason && dirty && (
        <p className="text-sm text-apt-text-muted" role="status">
          {blockedReason}
        </p>
      )}
      {saved && <p className="text-sm text-apt-green">Sync settings saved.</p>}
      <div className="flex justify-end">
        <Button type="submit" size="sm" disabled={busy || !canSave}>
          {busy ? "Saving…" : "Save sync settings"}
        </Button>
      </div>
    </form>
  );
}

/** Why `subreddits` isn't submittable as-is, or null (each entry, after stripping a leading r/,
 *  must match the backend's SUBREDDIT_NAME_PATTERN; a blank list is fine — inbox-only sync).
 *  This IS RedditSyncSettings.onSave's check, and it names the offending entry, so the reason
 *  shown beside a disabled Save is the same sentence the click would have produced. */
function redditSubredditsBlockedReason(subreddits: string): string | null {
  const names = subreddits
    .split(",")
    .map((s) => s.trim().replace(/^r\//, ""))
    .filter(Boolean);
  // Client-side mirror of the backend's SUBREDDIT_NAME_PATTERN (integration/action.ts).
  const bad = names.find((s) => !/^[A-Za-z0-9_]{2,21}$/.test(s));
  return bad ? `"${bad}" is not a subreddit name (letters, digits, _; 2–21 chars).` : null;
}

/** Reddit-only per-connection sync settings (subreddit watchlist + keyword filter).
 *  Prefilled from the stored settings; empty lists are valid — an empty watchlist means
 *  inbox-only sync — so Save always sends both arrays and clearing a field clears the
 *  setting (deliberately, now that the user can SEE what is stored). */
function RedditSyncSettings({ connectionId, initial }: SyncSettingsFormProps) {
  const [subreddits, setSubreddits] = useState(() => strArray(initial.redditSubreddits).join(", "));
  const [keywords, setKeywords] = useState(() => strArray(initial.redditKeywords).join(", "));
  // The stored baseline this form was prefilled from — re-set to the just-saved input on a
  // successful save, so Save goes disabled again until the next edit rather than staying
  // clickable for a no-op re-save of what's already persisted.
  const [baselineSubreddits, setBaselineSubreddits] = useState(subreddits);
  const [baselineKeywords, setBaselineKeywords] = useState(keywords);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  const dirty = subreddits !== baselineSubreddits || keywords !== baselineKeywords;
  const blockedReason = redditSubredditsBlockedReason(subreddits);
  const canSave = dirty && blockedReason === null;

  // Same contract as GmailSyncSettings above: reported on `dirty`, keyed per connection.
  useReportSettingsDirty(`integration-sync-reddit-${connectionId}`, dirty);

  const subsId = `reddit-subs-${connectionId}`;
  const keywordsId = `reddit-keywords-${connectionId}`;

  async function onSave() {
    const redditSubreddits = subreddits
      .split(",")
      .map((s) => s.trim().replace(/^r\//, ""))
      .filter(Boolean);
    const block = redditSubredditsBlockedReason(subreddits);
    if (block) {
      setError(block);
      return;
    }
    const redditKeywords = keywords
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    setBusy(true);
    setError(null);
    setSaved(false);
    try {
      await integrationsApi.patchSettings(connectionId, { redditSubreddits, redditKeywords });
      if (alive.current) {
        setSaved(true);
        setBaselineSubreddits(subreddits);
        setBaselineKeywords(keywords);
      }
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "integration-connections", step: "reddit-settings" });
      if (alive.current) setError(errMsg(err, "Couldn't save sync settings."));
    } finally {
      if (alive.current) setBusy(false);
    }
  }

  return (
    <form
      className="flex flex-col gap-3 pt-1"
      onSubmit={(e) => {
        e.preventDefault();
        void onSave();
      }}
    >
      <div className="flex flex-col gap-2">
        <Label htmlFor={subsId}>Watched subreddits</Label>
        <Input
          id={subsId}
          value={subreddits}
          placeholder="LocalLLaMA, typescript"
          onChange={(e) => {
            setSubreddits(e.target.value);
            setSaved(false);
          }}
        />
        <p className="text-xs text-apt-text-muted">
          Comma-separated, no r/ prefix needed. Leave blank to sync only your inbox.
        </p>
      </div>
      <div className="flex flex-col gap-2">
        <Label htmlFor={keywordsId}>Keyword filter</Label>
        <Input
          id={keywordsId}
          value={keywords}
          placeholder="claude, agents"
          onChange={(e) => {
            setKeywords(e.target.value);
            setSaved(false);
          }}
        />
        <p className="text-xs text-apt-text-muted">
          Comma-separated. Only watched posts mentioning a keyword are kept; blank keeps everything.
        </p>
      </div>
      <ErrorText error={error} />
      {/* Why Save is grey — same reasoning as the Gmail form above: the gate makes onSave's own
          name check unreachable by click, so it has to be visible instead. */}
      {!error && blockedReason && dirty && (
        <p className="text-sm text-apt-text-muted" role="status">
          {blockedReason}
        </p>
      )}
      {saved && <p className="text-sm text-apt-green">Sync settings saved.</p>}
      <div className="flex justify-end">
        <Button type="submit" size="sm" disabled={busy || !canSave}>
          {busy ? "Saving…" : "Save sync settings"}
        </Button>
      </div>
    </form>
  );
}

/** Per-provider sync-settings forms, rendered under ONE shared Disclosure below — a new
 *  provider adds a map entry, not another JSX branch (mirrors PROVIDER_DATA_TABLES in
 *  IntegrationData.tsx). */
const SYNC_SETTINGS_BY_PROVIDER: Record<
  string,
  { subtitle: string; Form: (props: SyncSettingsFormProps) => ReactElement }
> = {
  gmail: { subtitle: "Labels & history window", Form: GmailSyncSettings },
  reddit: { subtitle: "Watchlist & keywords", Form: RedditSyncSettings },
  mailchimp: { subtitle: "Audiences to sync contacts for", Form: AudienceSyncSettings },
  klaviyo: { subtitle: "Lists to sync profiles for", Form: AudienceSyncSettings },
};

/**
 * Connection management for the selected provider (c12): the ecosystem's linked
 * accounts for THIS provider, each with a status badge, last-sync / last-error,
 * Sync now (503 "no worker" shown inline), Disconnect (confirmed via AlertModal),
 * and — for gmail and reddit — a small sync-settings form. Hosts the "Connect account" dialog.
 *
 * The ecosystem's connections are read through the shared cache, so returning to a provider paints
 * its accounts on the first frame and revalidates behind that paint. The section used to take the
 * pane's already-loaded list as a `connections` prop for the same reason; nothing passed it, so
 * every provider switch re-read the whole ecosystem. The cache is that seed, for real and for
 * every host.
 */
export function ProviderConnections({
  provider,
  ecosystemId,
  providerConfig,
  onConnectionsChanged,
}: {
  provider: ProviderCatalogEntry;
  ecosystemId: string;
  /** The saved provider-config instance shown in this detail (null while none exists). The
   *  connect flow sources its creds from it — its `id` becomes the connect's providerConfigId,
   *  and for oauth_instance its `config.instanceUrl` seeds the register call. */
  providerConfig: MaskedProviderConfig | null;
  /** Notify the pane when the connection set changes (connect / disconnect), so its
   *  master-list union — which lists a provider as long as it has ≥1 connection —
   *  reflects the change and the provider doesn't vanish/linger after connecting. */
  onConnectionsChanged?: () => void;
}) {
  const providerId = provider.providerId;
  const syncSettingsDef = SYNC_SETTINGS_BY_PROVIDER[providerId];
  const [dialogOpen, setDialogOpen] = useState(false);
  const [syncingId, setSyncingId] = useState<string | null>(null);
  const [syncNotes, setSyncNotes] = useState<Record<string, string>>({});
  const [disconnectTarget, setDisconnectTarget] = useState<SafeConnection | null>(null);
  const [disconnectError, setDisconnectError] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);
  const alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  // Keyed on the ECOSYSTEM, not the provider, because that is what the route returns: one read
  // serves every provider in the detail, so switching provider paints from cache instead of
  // re-reading the whole ecosystem — which is what a per-provider key would cost.
  //
  // `providerId` is deliberately absent from these deps. A new `load` identity is the hook's
  // refetch signal, so closing over the provider would fire a network read on every switch —
  // the exact cost this key exists to avoid.
  const loadConnections = useCallback(async () => {
    try {
      return await integrationsApi.listConnections(ecosystemId);
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "integration-connections", step: "load" });
      // `errMsg`'s wording, raised here so it survives the hook's own generic fallback.
      throw err instanceof Error ? err : new Error("Couldn't load connected accounts.");
    }
  }, [ecosystemId]);

  const {
    items,
    error: fetchError,
    reload,
  } = useResourceList<SafeConnection>(
    `ecosystem:${ecosystemId}:integration-connections`,
    loadConnections,
    { reportErrors: false },
  );
  const connections = items ? items.filter((c) => c.provider === providerId) : null;
  const loadError = disconnectError ?? fetchError;

  // Swallowing, because every caller below re-reads AFTER its own write succeeded: a failed
  // re-read must not be reported as a failed sync or disconnect. It still reaches the screen —
  // as `fetchError`.
  const refresh = useCallback(() => reload().catch(() => {}), [reload]);

  async function onSync(id: string) {
    setSyncingId(id);
    setSyncNotes((n) => {
      if (!(id in n)) return n;
      const rest = { ...n };
      delete rest[id];
      return rest;
    });
    try {
      await integrationsApi.sync(id);
      if (alive.current) setSyncNotes((n) => ({ ...n, [id]: "Sync started." }));
      await refresh();
    } catch (err) {
      if (!alive.current) return;
      if (isServiceUnavailable(err)) {
        setSyncNotes((n) => ({
          ...n,
          [id]: "Sync isn't available yet — no worker is running for this provider.",
        }));
      } else {
        reportUnexpectedAuthError(err, { feature: "integration-connections", step: "sync" });
        setSyncNotes((n) => ({ ...n, [id]: errMsg(err, "Sync failed.") }));
      }
    } finally {
      if (alive.current) setSyncingId(null);
    }
  }

  async function onConfirmDisconnect() {
    if (!disconnectTarget) return;
    setDeleting(true);
    setDisconnectError(null);
    try {
      await integrationsApi.disconnect(disconnectTarget.id);
      if (alive.current) setDisconnectTarget(null);
      await refresh();
      onConnectionsChanged?.();
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "integration-connections", step: "disconnect" });
      if (alive.current) setDisconnectError(errMsg(err, "Couldn't disconnect that account."));
    } finally {
      if (alive.current) setDeleting(false);
    }
  }

  const connectAction = (
    <Button size="sm" onClick={() => setDialogOpen(true)}>
      <Plug data-icon="inline-start" />
      Connect account
    </Button>
  );

  return (
    <DetailSection title="Connected accounts" action={connectAction}>
      <ErrorText error={loadError} />

      {/* A failed read leaves the rows null, where the pre-cache code substituted an empty array —
          so the error is what suppresses "Loading…" here, or a failure would spin forever. */}
      {connections === null ? (
        !fetchError && <p className="text-sm text-apt-text-muted">Loading…</p>
      ) : connections.length === 0 ? (
        <p className="text-sm text-apt-text-muted">No account connected.</p>
      ) : (
        <List>
          {connections.map((c) => {
            const title = c.displayName || c.username || c.externalAccountId || provider.displayName;
            const note = syncNotes[c.id];
            return (
              <ListItem key={c.id} className="flex-col items-stretch gap-2 py-3">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex min-w-0 flex-col gap-1">
                    <span className="truncate text-sm font-medium text-apt-text">{title}</span>
                    <span className="text-xs text-apt-text-muted">{formatSync(c.lastSyncAt)}</span>
                    {c.lastError && (
                      <span className="text-xs text-apt-red">{c.lastError}</span>
                    )}
                  </div>
                  <Badge variant={statusVariant(c.status)}>{c.status}</Badge>
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => void onSync(c.id)}
                    disabled={syncingId === c.id}
                  >
                    <RefreshCw data-icon="inline-start" />
                    {syncingId === c.id ? "Syncing…" : "Sync now"}
                  </Button>
                  <Button
                    variant="destructive-ghost"
                    size="sm"
                    onClick={() => setDisconnectTarget(c)}
                  >
                    Disconnect
                  </Button>
                </div>
                {note && <p className="text-xs text-apt-text-muted">{note}</p>}
                {syncSettingsDef && (
                  <Disclosure title="Sync settings" subtitle={syncSettingsDef.subtitle}>
                    <syncSettingsDef.Form connectionId={c.id} initial={settingsOf(c)} />
                  </Disclosure>
                )}
              </ListItem>
            );
          })}
        </List>
      )}

      <ConnectAccountDialog
        provider={provider}
        ecosystemId={ecosystemId}
        providerConfig={providerConfig}
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        onConnected={() => {
          void refresh();
          onConnectionsChanged?.();
        }}
      />

      <AlertModal
        open={disconnectTarget != null}
        tone="error"
        title="Disconnect account"
        description={
          disconnectTarget
            ? `Disconnect ${
                disconnectTarget.displayName ||
                disconnectTarget.username ||
                provider.displayName
              }? This removes the connection and tombstones the data it synced.`
            : undefined
        }
        confirmLabel="Disconnect"
        confirmVariant="destructive"
        cancelLabel="Cancel"
        busy={deleting}
        onConfirm={() => void onConfirmDisconnect()}
        onCancel={() => setDisconnectTarget(null)}
      />
    </DetailSection>
  );
}
