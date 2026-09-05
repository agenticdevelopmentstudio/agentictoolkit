"use client";
import { createContext, useContext, type ReactElement, type ReactNode } from "react";

// The host port on the dashboard side: what the panels need to know about the
// deployment they are mounted in, supplied ONCE at the host's provider root. Nothing
// in this package reads the environment or names a hostname — a panel that lacks a
// value renders without it (the telemetry cards drop their deep link) rather than
// guessing where the host's tools live.

/** Host-supplied settings. Every field is optional. */
export interface StatusHostSettings {
  /** The error tracker's UI — the Errors card's "GlitchTip ↗" deep link. */
  readonly glitchtipUrl?: string;
  /** The analytics UI (the app host, not the ingest host) — the Traffic card's "PostHog ↗" link. */
  readonly posthogUrl?: string;
}

const NONE: StatusHostSettings = {};

const StatusHostContext = createContext<StatusHostSettings>(NONE);

/** Mount at the host's provider root, above the board. Without one every panel
 *  sees the empty settings. */
export function StatusHostProvider({ settings, children }: { settings: StatusHostSettings; children: ReactNode }): ReactElement {
  return <StatusHostContext.Provider value={settings}>{children}</StatusHostContext.Provider>;
}

/** The host's settings, or the empty settings when no provider is mounted. */
export function useStatusHost(): StatusHostSettings {
  return useContext(StatusHostContext);
}
