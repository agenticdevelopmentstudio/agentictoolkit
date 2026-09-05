"use client";

import { type ReactNode, type ReactElement } from "react";
import { useStatusUser } from "../header-auth";

const mono = "var(--mono,ui-monospace,monospace)";

/**
 * Gate for the board routes: a `pending` user (signed up but not yet approved) sees a
 * "not approved yet" notice instead of the dashboard. Authentication itself is
 * enforced by proxy.ts (no session → redirect to /login); this only distinguishes
 * pending from approved (viewer/admin). Until /api/auth/me ships it 404s → role
 * unknown → render the dashboard (the proxy already guaranteed a session).
 */
export function HomeGate({ children }: { children: ReactNode }): ReactElement {
  const { user } = useStatusUser();

  if (user?.role === "pending") {
    return (
      <main
        style={{
          flex: 1,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: 16,
          padding: "10vh 24px",
          textAlign: "center",
          color: "var(--color-apt-text)",
        }}
      >
        <h1 style={{ fontFamily: mono, fontSize: 22, fontWeight: 600, margin: 0 }}>Not approved yet</h1>
        <p style={{ opacity: 0.7, fontSize: 15, margin: 0 }}>Your account is pending approval. Check back soon.</p>
      </main>
    );
  }
  return <>{children}</>;
}
