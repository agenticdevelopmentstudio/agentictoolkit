"use client";

import { useState, useCallback, useRef, type FormEvent, type ReactElement } from "react";
import Link from "next/link";
import { Search } from "lucide-react";
import { Avatar, AvatarImage, AvatarFallback } from "@agenticdevelopertoolkit/ui/components/avatar";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { PROFILE_FRAME_CLASS } from "./frame";

// ── Types ─────────────────────────────────────────────────────────────────────

/** One hit from `GET /public/users/search`. Structurally the backend's
 *  `PrincipalSearchHit` (routes/principal-search.ts) — declared here rather than imported so
 *  this package stays free of the generated API types, the same arrangement `UserCardDto`
 *  has in @agenticdevelopertoolkit/ui. `kind` is what makes the merged namespace legible; see the
 *  React key on the result row for why it is not decoration. */
type SearchHit = {
  slug: string;
  displayName: string | null;
  avatarUrl: string | null;
  kind: "user" | "organization";
};

type SearchState =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "success"; hits: SearchHit[] }
  | { status: "error"; message: string };

// ── Helpers ───────────────────────────────────────────────────────────────────

function initials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase() ?? "")
    .join("");
}

// ── Component ─────────────────────────────────────────────────────────────────

/**
 * Shown when `/<slug>` or `/<slug>/profile` resolves to neither a feature nor a principal the
 * viewer may see. A principal is a user OR an organization — they share one slug namespace —
 * and the backend returns 404 both for a slug that does not exist and for one whose owner has
 * not admitted this viewer, so this page never reveals which it was.
 *
 * Includes a search box that calls `GET /api/public/users/search?q=<query>` — one endpoint over
 * both namespaces, which is why each hit carries its `kind`.
 *
 * Lives in @agentic-toolkit/adh rather than in the hub: every site in the fleet renders a
 * profile now, so every site can miss one.
 */
export function ProfileNotFound(): ReactElement {
  const [query, setQuery] = useState("");
  const [search, setSearch] = useState<SearchState>({ status: "idle" });
  // Tracks the AbortController for the most recent in-flight request so that
  // rapid successive searches cancel earlier ones and never apply stale results.
  const abortRef = useRef<AbortController | null>(null);

  const handleSearch = useCallback(async (q: string): Promise<void> => {
    const trimmed = q.trim();
    if (!trimmed) return;

    // Cancel any previous in-flight request before starting a new one.
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    setSearch({ status: "loading" });
    try {
      const res = await fetch(
        `/api/public/users/search?q=${encodeURIComponent(trimmed)}`,
        { signal: controller.signal },
      );
      if (!res.ok) throw new Error(`Search failed (${res.status})`);
      const hits = (await res.json()) as SearchHit[];
      setSearch({ status: "success", hits });
    } catch (err) {
      // Ignore AbortError — a newer request superseded this one.
      if (err instanceof DOMException && err.name === "AbortError") return;
      setSearch({
        status: "error",
        message:
          err instanceof Error ? err.message : "Search failed. Try again.",
      });
    }
  }, []);

  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    void handleSearch(query);
  };

  return (
    <main className={PROFILE_FRAME_CLASS}>
      <div className="rounded-xl border border-apt-border bg-apt-bg p-8">
        {/* ── Message ─────────────────────────────────────────────────── */}
        <h1 className="font-serif text-2xl font-medium text-apt-text sm:text-3xl">
          Profile not found
        </h1>
        <p className="mt-3 text-apt-text-muted">
          This profile doesn&apos;t exist, or its owner has chosen not to show it
          to you.
        </p>

        {/* ── Search ──────────────────────────────────────────────────── */}
        <div className="mt-8">
          <div
            className="mb-3 font-mono text-[0.6rem] uppercase tracking-[0.1em] text-apt-text-dim"
            id="profile-search-label"
          >
            Search for someone else
          </div>

          <form
            onSubmit={onSubmit}
            role="search"
            aria-labelledby="profile-search-label"
          >
            <div className="flex gap-2">
              <label htmlFor="profile-search" className="sr-only">
                Search profiles by name or slug
              </label>
              <Input
                id="profile-search"
                type="search"
                placeholder="Name or @slug…"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                className="flex-1"
              />
              <Button
                type="submit"
                size="default"
                disabled={!query.trim() || search.status === "loading"}
                aria-label="Search profiles"
              >
                <Search className="size-4" aria-hidden="true" />
              </Button>
            </div>
          </form>

          {/* Loading */}
          {search.status === "loading" && (
            <p
              className="mt-4 text-sm text-apt-text-muted"
              role="status"
              aria-live="polite"
            >
              Searching…
            </p>
          )}

          {/* Error. The `aria-live="polite"` this line used to carry down from the
              "Searching…" block above OVERRODE the assertive that `role="alert"`
              implies, so a failed search waited its turn behind whatever else the
              screen reader was saying. ErrorText's plain `role="alert"` is the
              fleet's answer and announces it. */}
          {search.status === "error" && (
            <ErrorText error={search.message} className="mt-4" />
          )}

          {/* Results */}
          {search.status === "success" && (
            <div aria-live="polite">
              {search.hits.length === 0 ? (
                <p className="mt-4 text-sm text-apt-text-muted">
                  Nothing found.
                </p>
              ) : (
                <ul
                  className="mt-4 space-y-2"
                  aria-label="Search results"
                >
                  {search.hits.map((hit) => {
                    const displayName = hit.displayName ?? hit.slug;
                    return (
                      // The key carries the KIND, not the slug alone. The search merged two
                      // namespaces into one response and a user and an organization may hold
                      // the same slug in different tables, so a slug-only key can collide —
                      // and two rows with one key make React reuse the wrong DOM node, showing
                      // an organization wearing a person's face. An index key would be no
                      // better: the list re-renders as the query changes, which is the same
                      // bug in a form that is harder to see.
                      <li key={`${hit.kind}:${hit.slug}`}>
                        <Link
                          href={`/${encodeURIComponent(hit.slug)}`}
                          className="flex items-center gap-3 rounded-lg border border-apt-border bg-apt-surface px-4 py-3 text-sm transition-colors hover:border-apt-border-strong hover:bg-apt-surface-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-apt-gold/40"
                        >
                          <Avatar className="size-8 shrink-0">
                            {hit.avatarUrl && (
                              <AvatarImage
                                src={hit.avatarUrl}
                                alt=""
                                aria-hidden="true"
                              />
                            )}
                            <AvatarFallback className="text-xs">
                              {initials(displayName)}
                            </AvatarFallback>
                          </Avatar>
                          <div className="min-w-0">
                            <div className="font-medium text-apt-text">
                              {displayName}
                            </div>
                            <div className="font-mono text-xs text-apt-text-muted">
                              @{hit.slug}
                              {" · "}
                              {hit.kind === "organization" ? "org" : "user"}
                            </div>
                          </div>
                        </Link>
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>
          )}
        </div>
      </div>
    </main>
  );
}
