"use client";

import { useEffect, useState, type ReactElement } from "react";
import { cn } from "../lib/utils";
import { railLinkVariants } from "@agenticdevelopertoolkit/ui/lib/nav-rail";
import { RequestsPane } from "../invitations/RequestsPane";
import { PendingUsersPane } from "../invitations/PendingUsersPane";
import { InvitesPane } from "../invitations/InvitesPane";

const TOPICS = [
  { id: "requests", label: "Requests" },
  { id: "pending", label: "Pending Users" },
  { id: "invites", label: "Invites" },
] as const;
type TopicId = (typeof TOPICS)[number]["id"];

export function InvitationsPane(): ReactElement {
  const [topic, setTopic] = useState<TopicId>("requests");

  // Deep-link the active sub-tab: seed from ?tab= on mount (so a shared link / reload
  // restores the tab — and lets each pane's own ?<paramKey>= row selection resolve
  // against the right pane), and mirror it on change via history.replaceState (no
  // remount, no history spam). An absent/unknown ?tab falls back to "requests".
  useEffect(() => {
    const t = new URLSearchParams(window.location.search).get("tab");
    if (t && TOPICS.some((x) => x.id === t)) setTopic(t as TopicId);
  }, []);

  function selectTopic(next: TopicId): void {
    setTopic(next);
    const url = new URL(window.location.href);
    url.searchParams.set("tab", next);
    window.history.replaceState(null, "", url);
  }

  return (
    <div className="flex h-[calc(100vh-7rem)] flex-col">
      <h1 className="mb-4 text-2xl font-bold text-foreground">Invitations</h1>
      <div className="grid min-h-0 flex-1 grid-cols-[200px_1fr] gap-0">
        <aside className="border-r border-border pr-4 pt-1">
          <nav>
            <ul className="space-y-1">
              {TOPICS.map((t) => (
                <li key={t.id}>
                  <button
                    type="button"
                    onClick={() => selectTopic(t.id)}
                    className={cn(
                      railLinkVariants({ active: topic === t.id }),
                      "w-full text-left",
                    )}
                  >
                    {t.label}
                  </button>
                </li>
              ))}
            </ul>
          </nav>
        </aside>
        <div className="flex min-h-0 min-w-0 flex-col pl-6">
          {topic === "requests" && <RequestsPane />}
          {topic === "pending" && <PendingUsersPane />}
          {topic === "invites" && <InvitesPane />}
        </div>
      </div>
    </div>
  );
}
