"use client";

import { useMemo, useState, type ReactElement } from "react";
import { KeyRound } from "lucide-react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Badge } from "@agentic-toolkit/ui/components/badge";
import { Button } from "@agentic-toolkit/ui/components/button";
import { Input } from "@agentic-toolkit/ui/components/input";
import { Select } from "@agentic-toolkit/ui/components/select";
import { CopyButton } from "@agentic-toolkit/ui/components/copy-button";
import { AlertModal } from "@agentic-toolkit/ui/components/alert-modal";
import { ButtonBar, Field, type TopicLevel } from "@agentic-toolkit/ui/blocks";
import { useSettingsEntityLevel } from "../settings-level";
import { useEditorMutations } from "./use-editor-mutations";
import { EntityEditorShell, SectionErrorText, SectionPlaceholder } from "./section-chrome";

type TokenRole = "admin" | "user";
type TokenKind = "minted" | "device";

/** A token's metadata as the backend serialises it (dates as ISO strings). NEVER
 *  the hash or raw secret — the raw value exists only in the mint response. */
interface TokenRow {
  id: string;
  name: string;
  role: TokenRole;
  kind: TokenKind;
  prefix: string;
  createdAt: string;
  lastUsedAt: string | null;
  expiresAt: string | null;
  revokedAt: string | null;
}
/** The mint (POST) response — the ONE time the raw secret is ever returned. */
interface MintedToken extends TokenRow {
  token: string;
}

const NO_TOKENS: TokenRow[] = [];
const QUERY_KEY = ["status-tokens"] as const;

const blankDraft = (): { name: string; role: TokenRole; expiryDays: string } => ({
  name: "",
  role: "user",
  expiryDays: "",
});

function fmtDate(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString();
}

function isExpired(t: TokenRow): boolean {
  return !!t.expiresAt && new Date(t.expiresAt).getTime() <= Date.now();
}

/** The lifecycle badge shown on a row / in the detail — revoked wins over expired. */
function statusBadge(t: TokenRow): { label: string; variant: "neutral" | "orange" } | null {
  if (t.revokedAt) return { label: "revoked", variant: "neutral" };
  if (isExpired(t)) return { label: "expired", variant: "orange" };
  return null;
}

/** Read a backend error body (status' flat `{ error | message }` shape). */
async function readErr(res: Response, fallback: string): Promise<string> {
  const body = (await res.json().catch(() => null)) as { error?: string; message?: string } | null;
  return body?.error ?? body?.message ?? fallback;
}

/**
 * Admin-only "API tokens" section. Fetches /api/tokens (admin-gated) and
 * publishes the roster as the board hierarchy's entity level (`/settings/tokens/<id>`).
 * Tokens are NOT editable after mint, so the leaf is a read-only detail + a
 * Revoke button; the "New token" flow mints one (name + role + optional expiry)
 * and reveals the raw secret EXACTLY ONCE — rendered from the 201 response only,
 * held in local state (never the query cache), and never re-shown after dismissal.
 */
export function TokensSection({
  selectedId,
  onNavigate,
}: {
  /** URL-selected token id (`/settings/tokens/<id>`), owned by the board level. */
  selectedId: string | null;
  onNavigate: (id: string | null) => void;
}): ReactElement {
  const queryClient = useQueryClient();
  const { busy, error, setError, run } = useEditorMutations();

  const [creating, setCreating] = useState(false);
  const [draft, setDraft] = useState(blankDraft);
  // The one-time reveal payload. Local state, so a background refetch / the 60s
  // poll can't clobber it — only an explicit dismiss or roster navigation clears
  // it, and nothing ever re-populates it (the secret is never cached).
  const [minted, setMinted] = useState<MintedToken | null>(null);
  const [confirmingRevoke, setConfirmingRevoke] = useState(false);

  const { data, error: queryError } = useQuery<TokenRow[]>({
    queryKey: QUERY_KEY,
    // Throw on a non-OK response so react-query lands in its error branch — a
    // 401/500 body must never become "rows" for the roster level.
    queryFn: async (): Promise<TokenRow[]> => {
      const res = await fetch("/api/tokens");
      if (!res.ok) throw new Error(await readErr(res, `Request failed (${res.status})`));
      return (await res.json()) as TokenRow[];
    },
  });
  const tokens = data ?? NO_TOKENS;

  const current = !creating && selectedId ? (tokens.find((t) => t.id === selectedId) ?? null) : null;

  function mint(): void {
    void run(async () => {
      const days = draft.expiryDays.trim() === "" ? null : Number(draft.expiryDays);
      const expiresAt =
        days !== null && Number.isFinite(days) && days > 0
          ? new Date(Date.now() + days * 86_400_000).toISOString()
          : null;
      const res = await fetch("/api/tokens", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: draft.name.trim(), role: draft.role, expiresAt }),
      });
      if (!res.ok) throw new Error(await readErr(res, `Request failed (${res.status})`));
      const payload = (await res.json()) as MintedToken;
      // invalidateQueries never rejects (TanStack v5); the mint already succeeded.
      await queryClient.invalidateQueries({ queryKey: QUERY_KEY });
      setMinted(payload); // reveal-once — straight from the response, never cached
      setCreating(false);
      setDraft(blankDraft());
      onNavigate(payload.id);
    });
  }

  function revoke(): void {
    if (!current) return;
    const id = current.id;
    void run(async () => {
      const res = await fetch(`/api/tokens/${id}`, { method: "DELETE" });
      if (!res.ok) throw new Error(await readErr(res, `Request failed (${res.status})`));
      await queryClient.invalidateQueries({ queryKey: QUERY_KEY });
      // Stay on the row — the list keeps revoked tokens, so it now reads "revoked".
    });
  }

  // Publish the roster as the hierarchy's entity level; the leaf is the detail.
  const level = useMemo<TopicLevel>(
    () => ({
      id: "roster-tokens",
      title: "API tokens",
      items: tokens.map((t) => {
        const badge = statusBadge(t);
        const used = t.lastUsedAt ? fmtDate(t.lastUsedAt) : "never";
        const exp = t.expiresAt ? fmtDate(t.expiresAt) : "never";
        return {
          id: t.id,
          label: t.name,
          sublabel: `${t.role} · ${t.kind} · ${t.prefix} · used ${used} · exp ${exp}`,
          icon: <KeyRound size={16} aria-hidden />,
          trailing: badge ? (
            <Badge variant={badge.variant} title={badge.label} aria-label={badge.label}>
              {badge.label}
            </Badge>
          ) : undefined,
        };
      }),
      selectedId: creating ? null : selectedId,
      onSelect: (id) => {
        setError(null);
        setCreating(false);
        setMinted(null);
        onNavigate(id);
      },
      onClear: () => {
        setError(null);
        setCreating(false);
        setMinted(null);
        onNavigate(null);
      },
      onNew: () => {
        setError(null);
        setMinted(null);
        setDraft(blankDraft());
        setCreating(true);
        onNavigate(null);
      },
      newLabel: "New token",
      newActive: creating,
      emptyLabel: queryError ? "Failed to load tokens." : "No tokens yet.",
    }),
    [tokens, selectedId, creating, onNavigate, setError, queryError],
  );
  useSettingsEntityLevel(level);

  // The one-time reveal takes precedence over every other leaf state and survives
  // re-renders until the user dismisses it.
  if (minted) {
    return (
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">
        <ButtonBar showCreate={false} showDelete={false} ariaLabel="Token created">
          <div className="flex flex-1 items-center justify-end">
            <Button variant="secondary" size="sm" onClick={() => setMinted(null)}>
              Done
            </Button>
          </div>
        </ButtonBar>
        <div className="flex max-w-xl flex-col gap-3 p-4 font-mono">
          <div className="text-sm text-apt-text">Token “{minted.name}” created</div>
          <div className="flex items-start gap-2 rounded-lg border border-apt-border bg-apt-bg p-3">
            <code className="min-w-0 flex-1 break-all text-xs text-apt-text">{minted.token}</code>
            <CopyButton getText={() => minted.token} label="Copy token" />
          </div>
          <p className="text-xs text-apt-red">You will not see this token again — copy it now.</p>
        </div>
      </div>
    );
  }

  if (queryError instanceof Error) {
    return <SectionErrorText>{queryError.message}</SectionErrorText>;
  }

  // New-token form — mint on Save (creation lives on the roster's "+ New").
  if (creating) {
    return (
      <EntityEditorShell
        onCancel={() => {
          setError(null);
          setCreating(false);
          setDraft(blankDraft());
          onNavigate(null);
        }}
        onSave={mint}
        canSave={draft.name.trim() !== "" && !busy}
        saving={busy}
        onDelete={() => {}}
        canDelete={false}
        deleteConfirm={null}
        error={error}
      >
        <div className="flex max-w-md flex-col gap-3 p-4 font-mono">
          <Field label="Name">
            <Input value={draft.name} onChange={(e) => setDraft((d) => ({ ...d, name: e.target.value }))} aria-label="Token name" />
          </Field>
          <Field label="Role" className="max-w-40">
            <Select value={draft.role} aria-label="Token role" onChange={(e) => setDraft((d) => ({ ...d, role: e.target.value as TokenRole }))}>
              <option value="user">user</option>
              <option value="admin">admin</option>
            </Select>
          </Field>
          <Field label="Expiry (days — blank = no expiry)" className="max-w-40">
            <Input
              type="number"
              min={1}
              value={draft.expiryDays}
              placeholder="never"
              onChange={(e) => setDraft((d) => ({ ...d, expiryDays: e.target.value }))}
              aria-label="Expiry in days"
            />
          </Field>
        </div>
      </EntityEditorShell>
    );
  }

  if (!current) {
    return <SectionPlaceholder>Select a token to view it, or create a new one.</SectionPlaceholder>;
  }

  const badge = statusBadge(current);
  const canRevoke = !current.revokedAt;
  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <ButtonBar showCreate={false} showDelete={false} ariaLabel="Token actions">
        <div className="flex flex-1 items-center gap-2">
          <Button
            variant="ghost"
            size="sm"
            onClick={() => {
              setError(null);
              onNavigate(null);
            }}
          >
            Back
          </Button>
          {canRevoke && (
            <Button variant="destructive" size="sm" className="ml-auto" disabled={busy} onClick={() => setConfirmingRevoke(true)}>
              Revoke
            </Button>
          )}
        </div>
      </ButtonBar>
      {error && <SectionErrorText>{error}</SectionErrorText>}
      <dl className="grid max-w-md grid-cols-[max-content_1fr] gap-x-4 gap-y-2 p-4 font-mono text-xs">
        <dt className="text-apt-text-muted">Name</dt>
        <dd className="text-apt-text">{current.name}</dd>
        <dt className="text-apt-text-muted">Role</dt>
        <dd className="text-apt-text">{current.role}</dd>
        <dt className="text-apt-text-muted">Kind</dt>
        <dd className="text-apt-text">{current.kind}</dd>
        <dt className="text-apt-text-muted">Prefix</dt>
        <dd className="text-apt-text">{current.prefix}…</dd>
        <dt className="text-apt-text-muted">Created</dt>
        <dd className="text-apt-text">{fmtDate(current.createdAt)}</dd>
        <dt className="text-apt-text-muted">Last used</dt>
        <dd className="text-apt-text">{current.lastUsedAt ? fmtDate(current.lastUsedAt) : "never"}</dd>
        <dt className="text-apt-text-muted">Expires</dt>
        <dd className="text-apt-text">{current.expiresAt ? fmtDate(current.expiresAt) : "never"}</dd>
        {badge && (
          <>
            <dt className="text-apt-text-muted">Status</dt>
            <dd>
              <Badge variant={badge.variant}>{badge.label}</Badge>
            </dd>
          </>
        )}
      </dl>
      <AlertModal
        open={confirmingRevoke}
        title={`Revoke token “${current.name}”?`}
        description="Any client using it stops working immediately. This cannot be undone."
        tone="error"
        destructive
        confirmLabel="Revoke"
        cancelLabel="Cancel"
        onConfirm={() => {
          setConfirmingRevoke(false);
          revoke();
        }}
        onCancel={() => setConfirmingRevoke(false)}
      />
    </div>
  );
}
