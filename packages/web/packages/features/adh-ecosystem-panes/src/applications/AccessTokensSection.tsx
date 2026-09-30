"use client";

import { useCallback, useState } from "react";
import { Plus, Trash2 } from "lucide-react";

import { useResourceList } from "@agentic-toolkit/data";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Disclosure } from "@agenticdevelopertoolkit/ui/components/disclosure";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { List, ListItem } from "@agenticdevelopertoolkit/ui/components/list";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { applicationsPrototypeApi, type AccessToken } from "../api/applications-prototype";
import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";

/**
 * Access tokens for an application — backed by the real
 * /ecosystem/applications/:appId/tokens API. Creating a token reveals the full
 * secret exactly once; the list is cached per application and refreshed after each
 * change, independent of the unsaved field edits.
 *
 * Only the PREFIX of each token is in this response — the secret exists in the create
 * response and nowhere else — so what is cached here is metadata, not a credential.
 */
export function AccessTokensSection({ appId }: { appId: string }) {
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [revealed, setRevealed] = useState<string | null>(null);
  const [mutationError, setMutationError] = useState<string | null>(null);

  // Reports under THIS section's telemetry context rather than the hook's generic one, which is
  // what `reportErrors: false` below is for — otherwise one failure is reported twice.
  const loadTokens = useCallback(async () => {
    try {
      return await applicationsPrototypeApi.listTokens(appId);
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "access-tokens", step: "load" });
      throw err instanceof Error ? err : new Error("Failed to load tokens.");
    }
  }, [appId]);

  // Cached per application, so reopening an app's tokens paints them on the first frame and
  // re-reads behind that paint.
  const {
    items,
    error: loadError,
    reload,
  } = useResourceList<AccessToken>(`application:${appId}:access-tokens`, loadTokens, {
    reportErrors: false,
  });
  const tokens = items ?? [];
  const error = mutationError ?? loadError;

  // Swallowing, because `create`/`revoke` re-read AFTER their own write succeeded: a failed
  // re-read must not be reported as a failed create or revoke. It still reaches the screen — as
  // `loadError`.
  const load = useCallback(() => reload().catch(() => {}), [reload]);

  async function create() {
    setBusy(true);
    setMutationError(null);
    try {
      const { secret } = await applicationsPrototypeApi.createToken(appId, name);
      setRevealed(secret);
      setName("");
      setCreating(false);
      await load();
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "access-tokens", step: "save" });
      setMutationError(err instanceof Error ? err.message : "Failed to create token.");
    } finally {
      setBusy(false);
    }
  }

  async function revoke(tokenId: string, tokenName: string) {
    if (!confirm(`Revoke token "${tokenName}"? Applications using it will lose access.`)) return;
    try {
      await applicationsPrototypeApi.revokeToken(appId, tokenId);
      await load();
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "access-tokens", step: "delete" });
      setMutationError(err instanceof Error ? err.message : "Failed to revoke token.");
    }
  }

  return (
    <Disclosure
      title="Access tokens"
      subtitle={`${tokens.length} token${tokens.length === 1 ? "" : "s"}`}
      actions={
        // No API button here: the application's detail header carries the one API button, left of
        // its Help — a second one inside the body could not say which endpoint was whose.
        <Button type="button" variant="outline" size="sm" onClick={() => setCreating((v) => !v)}>
          <Plus data-icon="inline-start" />
          New token
        </Button>
      }
    >
      <div className="flex flex-col gap-3">
        {revealed && (
          <div className="rounded-md border border-apt-gold/40 bg-apt-gold/10 p-3">
            <p className="mb-2 text-xs text-apt-text-muted">
              Copy this token now — you won&apos;t be able to see it again.
            </p>
            <div className="flex items-center gap-2">
              <Input readOnly value={revealed} onFocus={(e) => e.currentTarget.select()} />
              <Button
                type="button"
                variant="secondary"
                size="sm"
                onClick={() => void navigator.clipboard?.writeText(revealed)}
              >
                Copy
              </Button>
              <Button type="button" variant="ghost" size="sm" onClick={() => setRevealed(null)}>
                Done
              </Button>
            </div>
          </div>
        )}

        {creating && (
          <div className="flex items-end gap-2">
            <div className="flex flex-1 flex-col gap-2">
              <Label htmlFor={`tok-name-${appId}`}>Token name</Label>
              <Input
                id={`tok-name-${appId}`}
                value={name}
                placeholder="CI deploy"
                onChange={(e) => setName(e.target.value)}
              />
            </div>
            <Button type="button" onClick={create} disabled={busy}>
              {busy ? "Creating…" : "Create"}
            </Button>
          </div>
        )}

        <ErrorText error={error} />

        {tokens.length === 0 ? (
          <p className="text-sm text-apt-text-muted">No tokens yet.</p>
        ) : (
          <List>
            {tokens.map((t) => (
              <ListItem key={t.id} className="justify-between bg-apt-bg py-2">
                <span className="flex min-w-0 flex-col">
                  <span className="truncate text-sm text-apt-text">{t.name}</span>
                  <span className="truncate text-xs text-apt-text-muted">
                    <code>{t.prefix}…</code>
                  </span>
                </span>
                <Button
                  type="button"
                  variant="destructive-ghost"
                  size="icon-sm"
                  onClick={() => revoke(t.id, t.name)}
                  title="Revoke token"
                >
                  <Trash2 />
                </Button>
              </ListItem>
            ))}
          </List>
        )}
      </div>
    </Disclosure>
  );
}
