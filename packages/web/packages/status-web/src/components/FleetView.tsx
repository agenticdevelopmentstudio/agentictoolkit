"use client";
import { type ReactElement } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { StatusDot } from "./StatusDot";
import { timeAgo } from "../lib/time-ago";
import { useNow } from "../hooks/use-now";
import { useStatusUser } from "../hooks/useStatusUser";
import { COLORS, PALETTE } from "../lib/colors";
// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface FleetMemberPayload {
  generatedAt?: string;
  overall?: string | null;
  services?: Array<{ status: string }>;
  openIssues?: unknown[];
}

interface FleetMember {
  self: boolean;
  label: string;
  baseUrl: string | null;
  overall: string | null;
  reachable: boolean;
  fetchedAt: string;
  payload: unknown;
}

// ---------------------------------------------------------------------------
// Query hook
// ---------------------------------------------------------------------------

function useFleet() {
  return useQuery<FleetMember[]>({
    queryKey: ["fleet"],
    queryFn: async () => {
      const r = await fetch("/api/fleet");
      if (!r.ok) {
        const detail = await r
          .json()
          .then((b: { error?: string }) => b.error)
          .catch(() => null);
        throw new Error(detail || `status ${r.status}`);
      }
      return r.json();
    },
    refetchOnWindowFocus: true,
    staleTime: 30_000,
  });
}

// ---------------------------------------------------------------------------
// Member card
// ---------------------------------------------------------------------------

function statusLabel(overall: string | null, reachable: boolean): string {
  if (!reachable) return "unreachable";
  if (!overall) return "unknown";
  return overall;
}

// Map fleet overall values to StatusDot status keys.
// The backend returns: 'healthy' | 'degraded' | 'down' | null.
// StatusDot understands HEALTH_COLORS keys (healthy/degraded/down/unknown)
// and OVERALL_COLORS keys (operational/degraded/major_outage/unknown).
// Use the HEALTH_COLORS keys since that's what the fleet backend returns.
function dotStatus(overall: string | null, reachable: boolean): string {
  if (!reachable) return "unknown";
  return overall ?? "unknown";
}

function FleetMemberCard({ member, nowMs }: { member: FleetMember; nowMs: number }): ReactElement {
  const payload = member.payload as FleetMemberPayload | null | undefined;
  const dot = dotStatus(member.overall, member.reachable);
  const label = statusLabel(member.overall, member.reachable);

  // Freshness — how long ago we last polled this peer
  const ageStr = member.fetchedAt ? timeAgo(member.fetchedAt, nowMs) : null;
  const freshnessLabel = ageStr
    ? ageStr === "just now"
      ? "updated just now"
      : `updated ${ageStr} ago`
    : "—";

  // Summarize service counts + open issues from the payload when available
  const serviceCount = payload?.services?.length ?? null;
  const openIssues = Array.isArray((payload as { openIssues?: unknown[] } | null | undefined)?.openIssues)
    ? (payload as { openIssues: unknown[] }).openIssues.length
    : null;

  return (
    <div
      style={{
        background: PALETTE.surface,
        border: `1px solid ${PALETTE.border}`,
        borderRadius: 6,
        padding: "14px 18px",
        display: "flex",
        flexDirection: "column",
        gap: 10,
        minWidth: 0,
      }}
    >
      {/* Header row: label + self badge + status dot + status label */}
      <div style={{ display: "flex", alignItems: "center", gap: 10, minWidth: 0 }}>
        <StatusDot status={dot} size={10} />
        <span
          style={{
            fontWeight: 700,
            fontSize: 13,
            letterSpacing: "0.03em",
            color: PALETTE.text,
            overflow: "hidden",
            textOverflow: "ellipsis",
            whiteSpace: "nowrap",
            flex: 1,
            minWidth: 0,
          }}
          title={member.label}
        >
          {member.label}
        </span>
        {member.self && (
          <span
            style={{
              fontSize: 10,
              fontWeight: 600,
              letterSpacing: "0.05em",
              color: PALETTE.blue,
              border: `1px solid ${PALETTE.blue}`,
              borderRadius: 3,
              padding: "1px 5px",
              flexShrink: 0,
            }}
          >
            THIS MONITOR
          </span>
        )}
      </div>

      {/* Status row */}
      <div style={{ display: "flex", alignItems: "center", gap: 16, flexWrap: "wrap" }}>
        <span
          style={{
            fontFamily: "var(--mono,ui-monospace,monospace)",
            fontSize: 12,
            fontWeight: 600,
            letterSpacing: "0.06em",
            color: !member.reachable || !member.overall
              ? PALETTE.muted
              : member.overall === "healthy"
                ? PALETTE.green
                : member.overall === "degraded"
                  ? PALETTE.amber
                  : PALETTE.red,
          }}
        >
          {label.toUpperCase()}
        </span>

        {/* Service / issue summary from payload */}
        {serviceCount !== null && (
          <span style={{ fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 11, color: PALETTE.muted }}>
            {serviceCount} {serviceCount === 1 ? "service" : "services"}
          </span>
        )}
        {openIssues !== null && openIssues > 0 && (
          <span style={{ fontFamily: "var(--mono,ui-monospace,monospace)", fontSize: 11, color: PALETTE.amber }}>
            ⚠ {openIssues} {openIssues === 1 ? "issue" : "issues"}
          </span>
        )}
      </div>

      {/* Footer row: URL + freshness */}
      <div style={{ display: "flex", alignItems: "center", gap: 14, flexWrap: "wrap" }}>
        {member.baseUrl && !member.self && (
          <span
            style={{
              fontFamily: "var(--mono,ui-monospace,monospace)",
              fontSize: 11,
              color: PALETTE.dim,
              overflow: "hidden",
              textOverflow: "ellipsis",
              whiteSpace: "nowrap",
              flex: 1,
              minWidth: 0,
            }}
            title={member.baseUrl}
          >
            {member.baseUrl}
          </span>
        )}
        <span
          style={{
            fontFamily: "var(--mono,ui-monospace,monospace)",
            fontSize: 11,
            color: PALETTE.dim,
            marginLeft: "auto",
            whiteSpace: "nowrap",
          }}
        >
          {freshnessLabel}
        </span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Divergence note
// ---------------------------------------------------------------------------

/** Returns true if two or more reachable members disagree on overall status. */
function hasDivergence(members: FleetMember[]): boolean {
  const reachableOveralls = members
    .filter((m) => m.reachable && m.overall !== null)
    .map((m) => m.overall);
  if (reachableOveralls.length < 2) return false;
  const first = reachableOveralls[0];
  return reachableOveralls.some((o) => o !== first);
}

// ---------------------------------------------------------------------------
// FleetView
// ---------------------------------------------------------------------------

export function FleetView(): ReactElement {
  const query = useFleet();
  const nowMs = useNow(30_000);
  const user = useStatusUser();

  const sharedStyle: React.CSSProperties = {
    display: "flex",
    flexDirection: "column",
    flex: 1,
    minHeight: 0,
    width: "100%",
    background: PALETTE.bg,
    color: PALETTE.text,
    fontFamily: "var(--mono,ui-monospace,monospace)",
    fontSize: 13,
    lineHeight: 1.2,
  };

  if (query.isLoading) {
    return (
      <div style={{ ...sharedStyle, alignItems: "center", justifyContent: "center" }}>
        <span style={{ color: PALETTE.muted }}>Loading fleet…</span>
      </div>
    );
  }

  if (query.error || !query.data) {
    const msg = query.error instanceof Error ? query.error.message : "unknown error";
    return (
      <div style={{ ...sharedStyle, alignItems: "center", justifyContent: "center", padding: "0 16px", textAlign: "center" }}>
        <span style={{ color: PALETTE.red }}>Failed to load fleet — {msg}</span>
      </div>
    );
  }

  const members = query.data;
  const diverges = hasDivergence(members);

  return (
    <div style={sharedStyle}>
      {/* Header strip */}
      <div
        style={{
          flex: "0 0 auto",
          display: "flex",
          alignItems: "center",
          gap: 16,
          padding: "9px 16px",
          borderBottom: `1px solid ${PALETTE.border}`,
          background: `linear-gradient(180deg,${COLORS.surfaceMid},${COLORS.surfaceDeep})`,
        }}
      >
        <span style={{ fontWeight: 700, fontSize: 13, letterSpacing: "0.04em" }}>
          Fleet
        </span>
        <span style={{ fontSize: 12, color: PALETTE.muted }}>
          {members.length} {members.length === 1 ? "monitor" : "monitors"}
        </span>
        {diverges && (
          <span
            style={{
              marginLeft: "auto",
              fontFamily: "var(--mono,ui-monospace,monospace)",
              fontSize: 12,
              color: PALETTE.amber,
            }}
          >
            ⚠ peers disagree on overall status
          </span>
        )}
      </div>

      {/* Card grid */}
      <div
        style={{
          flex: 1,
          minHeight: 0,
          overflowY: "auto",
          padding: 16,
          display: "grid",
          gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))",
          gap: 12,
          alignContent: "start",
        }}
      >
        {members.map((member) => (
          <FleetMemberCard
            key={member.self ? "__self__" : (member.baseUrl ?? member.label)}
            member={member}
            nowMs={nowMs}
          />
        ))}
        {/* `/fleet` always returns THIS monitor, so the state worth calling out is "self
            only", i.e. no peers configured yet. Admins get sent to the roster that fixes
            it; everyone else just learns why it's bare. The length check is load-bearing:
            `every` is true for an empty array, so a failed/empty payload would otherwise
            claim "no peers configured" when the truth is that we don't know. */}
        {members.length > 0 && members.every((m) => m.self) && (
          <div style={{ color: PALETTE.muted, fontSize: 13 }}>
            {user?.role === "admin" ? (
              <>
                No peers yet — add the monitors this one should watch in{" "}
                <Link href="/settings/peers" style={{ color: PALETTE.blue, textDecoration: "underline" }}>
                  Settings ▸ Fleet peers
                </Link>
                .
              </>
            ) : (
              "No peers configured — this monitor is the whole fleet."
            )}
          </div>
        )}
      </div>
    </div>
  );
}
