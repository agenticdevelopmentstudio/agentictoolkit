"use client";

import { type ReactElement, useCallback, useEffect, useState } from "react";
import { Button } from "@agentic-toolkit/ui/components/button";

const mono = "var(--mono,ui-monospace,monospace)";

/** The screen's state machine. `pending` is the only state that offers the
 *  Approve/Deny actions; everything else is terminal or an entry prompt. */
type Phase = "prompt" | "loading" | "pending" | "handled" | "notfound" | "approved" | "denied" | "error";

interface Pending {
  label: string;
  status: "pending" | "approved" | "denied";
  createdAt: string;
  expiresAt: string;
}

/** Human "expires in N min" from an ISO instant (client-only, so no SSR skew). */
function expiryHint(iso: string): string {
  const ms = new Date(iso).getTime() - Date.now();
  if (ms <= 0) return "expired";
  const mins = Math.ceil(ms / 60_000);
  return `expires in ${mins} minute${mins === 1 ? "" : "s"}`;
}

/**
 * Device-authorization approval screen (reached via the `verification_uri` a CLI
 * prints, e.g. `/device?code=ABCD-2345`). This route is session-gated by the
 * proxy middleware (no session → /login), and the backend approval endpoints
 * additionally reject any non-session principal — so only a signed-in
 * viewer/admin lands here and can act. It GETs the pending request to show WHAT
 * is being approved, then POSTs Approve/Deny through the `/api` BFF.
 */
export function DeviceApproval({ initialCode }: { initialCode: string }): ReactElement {
  const [code, setCode] = useState(initialCode);
  const [phase, setPhase] = useState<Phase>(initialCode ? "loading" : "prompt");
  const [request, setRequest] = useState<Pending | null>(null);
  const [error, setError] = useState<string>("");
  const [busy, setBusy] = useState(false);

  const lookup = useCallback(async (userCode: string): Promise<void> => {
    const trimmed = userCode.trim();
    if (!trimmed) return;
    setPhase("loading");
    setError("");
    try {
      const res = await fetch(`/api/auth/device/pending?user_code=${encodeURIComponent(trimmed)}`);
      if (res.status === 404) {
        setPhase("notfound");
        return;
      }
      if (!res.ok) {
        setError(res.status === 403 ? "You must be signed in to approve a device." : "Something went wrong.");
        setPhase("error");
        return;
      }
      const body = (await res.json()) as Pending;
      if (body.status !== "pending") {
        setPhase("handled");
        return;
      }
      setRequest(body);
      setPhase("pending");
    } catch {
      setError("Could not reach the server.");
      setPhase("error");
    }
  }, []);

  // Auto-look up a code arriving in the URL (the CLI's deep link).
  useEffect(() => {
    if (initialCode) void lookup(initialCode);
  }, [initialCode, lookup]);

  const act = useCallback(
    async (decision: "approve" | "deny"): Promise<void> => {
      setBusy(true);
      setError("");
      try {
        const res = await fetch(`/api/auth/device/${decision}`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ user_code: code.trim() }),
        });
        if (res.status === 404) setPhase("notfound");
        else if (res.status === 409) setPhase("handled");
        else if (!res.ok) {
          setError("Something went wrong.");
          setPhase("error");
        } else setPhase(decision === "approve" ? "approved" : "denied");
      } catch {
        setError("Could not reach the server.");
        setPhase("error");
      } finally {
        setBusy(false);
      }
    },
    [code],
  );

  return (
    <div className="flex flex-1 items-center justify-center p-6">
      <div
        className="w-full max-w-md rounded-lg border border-apt-border bg-apt-surface p-6 text-apt-text"
        style={{ fontFamily: mono }}
      >
        <h1 className="text-lg font-semibold text-apt-text">Device authorization</h1>

        {phase === "prompt" && (
          <div className="mt-4 flex flex-col gap-3">
            <p className="text-sm text-apt-text-dim">Enter the code shown in your terminal.</p>
            <input
              value={code}
              onChange={(e) => setCode(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") void lookup(code);
              }}
              placeholder="XXXX-XXXX"
              aria-label="Device code"
              autoFocus
              className="rounded-md border border-apt-border bg-apt-bg px-3 py-2 text-sm text-apt-text outline-none focus:border-apt-accent"
              style={{ fontFamily: mono, letterSpacing: "0.15em" }}
            />
            <Button type="button" onClick={() => void lookup(code)} disabled={!code.trim()}>
              Continue
            </Button>
          </div>
        )}

        {phase === "loading" && <p className="mt-4 text-sm text-apt-text-dim">Looking up your request…</p>}

        {phase === "pending" && request && (
          <div className="mt-4 flex flex-col gap-4">
            <p className="text-sm text-apt-text-dim">
              A device is requesting access to your account:
            </p>
            <div className="rounded-md border border-apt-border bg-apt-bg px-4 py-3">
              <div className="text-sm font-semibold text-apt-text">{request.label || "device"}</div>
              <div className="mt-1 text-xs text-apt-text-dim">{expiryHint(request.expiresAt)}</div>
            </div>
            <p className="text-xs text-apt-text-dim">
              Approve only if you started this from your own terminal. The device will get a token with your
              access level.
            </p>
            <div className="flex gap-3">
              <Button type="button" onClick={() => void act("approve")} disabled={busy} className="flex-1">
                Approve
              </Button>
              <Button
                type="button"
                variant="outline"
                onClick={() => void act("deny")}
                disabled={busy}
                className="flex-1"
              >
                Deny
              </Button>
            </div>
          </div>
        )}

        {phase === "approved" && (
          <p className="mt-4 text-sm text-apt-green">Approved — return to your terminal.</p>
        )}
        {phase === "denied" && (
          <p className="mt-4 text-sm text-apt-text-dim">Denied. The device was not granted access.</p>
        )}
        {phase === "handled" && (
          <p className="mt-4 text-sm text-apt-text-dim">This request has already been handled.</p>
        )}
        {phase === "notfound" && (
          <p className="mt-4 text-sm text-apt-red">That code was not found or has expired.</p>
        )}
        {phase === "error" && <p className="mt-4 text-sm text-apt-red">{error || "Something went wrong."}</p>}
      </div>
    </div>
  );
}
