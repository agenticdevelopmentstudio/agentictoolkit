"use client";

import { useCallback, useEffect, useRef, useState, type ReactElement } from "react";
import { ExternalLink, Trash2 } from "lucide-react";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { List, ListItem } from "@agenticdevelopertoolkit/ui/components/list";
import { ListChooser, type ListChooserItem } from "@agenticdevelopertoolkit/ui/components/list-chooser";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { useResourceList } from "@agentic-toolkit/data";
import {
  projectArtifactsApi,
  type ArtifactDirection,
  type ProjectArtifact,
  type TargetDescriptor,
} from "@agentic-toolkit/data/projects";
import { FeatureTitle } from "@agentic-toolkit/resource";

/**
 * WHAT THE PROJECT HOLDS — the Contents topic.
 *
 * A project is not only a queue of work; it is also a PLACE that accumulates material. This
 * pane is the second half: the documents and saved links the project took IN (ingested) and the
 * ones it put OUT (produced). The two directions are shown as two lists rather than one list
 * with a column, because they answer different questions — "what am I working from" and "what
 * has this produced" — and a reader is almost always asking one of them.
 *
 * Everything here is kind-agnostic on purpose. The backend's target registry resolves each
 * stored `(kind, id)` pointer into the same four display fields whatever table it names, so this
 * pane never branches on kind: it renders the kind as a Badge and the resolution as a row. A
 * kind added to the registry appears in this pane, in a bundle built before that kind existed.
 *
 * The attach control follows the Participants idiom in the sibling Overview pane — a couple of
 * fields, an Add button, and a per-row ghost Trash2 with no confirm — with one upgrade: where
 * Participants asks for a raw actor id, this asks the backend what is attachable and offers the
 * answers by title. Detaching removes the project's CLAIM on something, never the thing itself,
 * which is what makes an undialogued Trash2 the honest affordance here.
 */

const DIRECTIONS: { value: ArtifactDirection; label: string }[] = [
  { value: "ingested", label: "Ingested" },
  { value: "produced", label: "Produced" },
];

/** How many candidates to pull PER KIND for the picker. The chooser filters what it was given,
 *  client-side, so this is also the point past which a workspace's content stops being
 *  reachable from here — deliberately the endpoint's maximum rather than its default. */
const CANDIDATE_LIMIT = 100;

/** A candidate's composite key. `ListChooser` commits a single string, and neither half of a
 *  target's address identifies it alone — two kinds may legitimately share an id.
 *
 *  The separator is a NUL because it is the one byte neither half can contain, so the join needs
 *  no escaping on either side. It is written as an ESCAPE and must stay that way: a literal
 *  control byte makes git treat the ENTIRE FILE as binary — no diff, no merge, no review — while
 *  being invisible in every editor, so nobody would find it by looking. */
function candidateKey(t: { kind: string; id: string }): string {
  return `${t.kind}\u0000${t.id}`;
}

/** The last visible segment of a kind ("content.markdown" → "markdown") — a Badge wants a word,
 *  and the schema prefix is the same on every row in the list, so it carries no information
 *  where it would cost the most width. */
function kindLabel(kind: string): string {
  const tail = kind.split(".").pop();
  return tail && tail.length > 0 ? tail : kind;
}

/** One attached row: the kind, the resolved title (a link when the target lives outside the
 *  platform), its supporting line, and the detach. */
function ArtifactRow({
  artifact,
  onDetach,
  detaching,
}: {
  artifact: ProjectArtifact;
  onDetach: () => void;
  detaching: boolean;
}): ReactElement {
  const target = artifact.target;
  return (
    <ListItem className="justify-between">
      <div className="flex min-w-0 items-center gap-2">
        <Badge variant="neutral">{kindLabel(artifact.targetKind)}</Badge>
        {target ? (
          <>
            {target.url ? (
              <a
                href={target.url}
                target="_blank"
                rel="noreferrer"
                className="flex min-w-0 items-center gap-1 truncate text-sm text-apt-text underline-offset-2 hover:underline"
              >
                <span className="truncate">{target.title}</span>
                <ExternalLink className="size-3 shrink-0" aria-hidden />
              </a>
            ) : (
              <span className="truncate text-sm text-apt-text">{target.title}</span>
            )}
            {target.subtitle && (
              <span className="hidden truncate text-xs text-apt-text-muted sm:inline">
                {target.subtitle}
              </span>
            )}
          </>
        ) : (
          // A pointer outlives what it points at — nothing rewrites links when a document is
          // deleted. Saying so beats hiding the row: the link is still a fact about the project,
          // and a silently shorter list is the harder thing to explain.
          <span className="truncate text-sm text-apt-text-muted italic">
            No longer available
          </span>
        )}
      </div>
      <Button
        variant="ghost"
        size="icon-sm"
        aria-label={`Detach ${target ? target.title : artifact.targetId}`}
        disabled={detaching}
        onClick={onDetach}
      >
        <Trash2 />
      </Button>
    </ListItem>
  );
}

export function ProjectContentsPane({
  projectId,
  title,
}: {
  projectId: string;
  title: string;
}): ReactElement {
  const [direction, setDirection] = useState<ArtifactDirection>("ingested");
  const [pick, setPick] = useState<string | null>(null);
  const [attaching, setAttaching] = useState(false);
  const [attachError, setAttachError] = useState<string | null>(null);
  const [detachingId, setDetachingId] = useState<string | null>(null);

  // Guards the attach/detach BUSY flags only; the list's own out-of-order and after-unmount
  // handling belongs to useResourceList below.
  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  // The attached links. The SAME `project:<id>:artifacts` cache key Overview's Material summary
  // reads, so arriving here from Overview paints from cache and settles behind it — and the
  // reload-after-write ordering (attach, reload; detach, reload — two GETs in flight, no
  // guarantee the first lands first) is the shared hook's, not a third hand-rolled copy of it.
  const loadArtifacts = useCallback(() => projectArtifactsApi.list(projectId), [projectId]);
  const {
    items: artifacts,
    reload: reloadArtifacts,
    error: loadError,
  } = useResourceList<ProjectArtifact>(`project:${projectId}:artifacts`, loadArtifacts);

  // Cached like the artifacts, so re-entering Material paints the picker's options too. The
  // fetcher SWALLOWS into an empty list rather than rethrowing: a picker that cannot be filled is
  // not an error worth a banner — the lists above still read, and the attach control's own empty
  // state says what happened. A fetcher that cannot fail has no error to report, so the hook's
  // error channel stays empty and nothing below reads one.
  const loadCandidates = useCallback(
    () =>
      projectArtifactsApi
        .attachable(projectId, { limit: CANDIDATE_LIMIT })
        .catch(() => [] as TargetDescriptor[]),
    [projectId],
  );
  const { items: candidateRows, reload: reloadCandidates } = useResourceList<TargetDescriptor>(
    `project:${projectId}:attachable`,
    loadCandidates,
  );
  const candidates = candidateRows ?? [];

  async function attach(): Promise<void> {
    const chosen = candidates.find((c) => candidateKey(c) === pick);
    if (!chosen) return;
    setAttaching(true);
    setAttachError(null);
    try {
      await projectArtifactsApi.link(projectId, {
        direction,
        targetKind: chosen.kind,
        targetId: chosen.id,
      });
      setPick(null);
      // The candidates too, and this is what the cache made necessary: a hand-rolled effect
      // re-read them on the next mount, so a just-attached target dropped out of the picker by
      // itself. A cached list would keep offering it for the whole staleness window instead.
      //
      // The reloads' own promises reject on failure; the hook has already surfaced the artifacts'
      // as `loadError`, so there is nothing left for this caller to do with either.
      await Promise.all([reloadArtifacts(), reloadCandidates()]).catch(() => {});
    } catch (e) {
      setAttachError(e instanceof Error ? e.message : "Failed to attach.");
    } finally {
      if (mounted.current) setAttaching(false);
    }
  }

  async function detach(artifact: ProjectArtifact): Promise<void> {
    setDetachingId(artifact.id);
    setAttachError(null);
    try {
      await projectArtifactsApi.unlink(projectId, artifact.id);
      // The detached target is attachable again, so the picker has to hear about it too.
      await Promise.all([reloadArtifacts(), reloadCandidates()]).catch(() => {});
    } catch (e) {
      setAttachError(e instanceof Error ? e.message : "Failed to detach.");
    } finally {
      if (mounted.current) setDetachingId(null);
    }
  }

  const chooserItems: ListChooserItem[] = candidates.map((c) => ({
    value: candidateKey(c),
    label: c.title,
  }));

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <FeatureTitle
        title={title}
        api={{
          path: "/project/projects/{id}/artifacts",
          pathValues: { id: projectId },
          title: "Project contents API",
        }}
      />
      <section className="flex min-w-0 flex-1 flex-col gap-6 overflow-y-auto px-6 py-4">
        {/* ── Attach ───────────────────────────────────────────────────── */}
        <div className="flex max-w-xl flex-col gap-3">
          <div className="flex flex-wrap items-end gap-3">
            <Field label="Direction" className="w-40">
              <Select
                value={direction}
                onChange={(e) => {
                  setAttachError(null);
                  setDirection(e.target.value as ArtifactDirection);
                }}
              >
                {DIRECTIONS.map((d) => (
                  <option key={d.value} value={d.value}>
                    {d.label}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Content" className="min-w-56 flex-1">
              <ListChooser
                items={chooserItems}
                value={pick}
                // Nothing here can be CREATED by picking it — the list is what already exists
                // and is reachable, so typed text that matches nothing is not an entry to add.
                allowCreate={false}
                onChange={(value) => {
                  setAttachError(null);
                  setPick(value);
                }}
                // The accessible name matches the Field's visible caption on purpose — the
                // trigger's aria-label overrides the wrapping Label, so letting the two say
                // different things is how a control ends up unaddressable by its own caption.
                ariaLabel="Content"
                inputLabel="Filter content"
                triggerPlaceholder="Choose content…"
                placeholder="Filter…"
                emptyLabel="Nothing available to attach"
              />
            </Field>
            <Button onClick={() => void attach()} disabled={attaching || pick === null}>
              Attach
            </Button>
          </div>
          <ErrorText error={attachError} />
          <ErrorText error={loadError} />
        </div>

        {/* ── What the project holds ───────────────────────────────────── */}
        {artifacts === null ? (
          // Only while the read is genuinely outstanding: with the error above, "Loading…" is a
          // promise the pane is not keeping, and the two "Nothing … yet" empty states would each
          // assert a fact the pane does not have.
          loadError ? null : (
            <p className="text-sm text-apt-text-muted">Loading…</p>
          )
        ) : (
          DIRECTIONS.map((d) => {
            const rows = artifacts.filter((a) => a.direction === d.value);
            return (
              <div key={d.value} className="flex max-w-xl flex-col gap-3">
                <h3 className="text-sm font-semibold text-apt-text">{d.label}</h3>
                {rows.length === 0 ? (
                  <EmptyState
                    title={
                      d.value === "ingested"
                        ? "Nothing ingested yet."
                        : "Nothing produced yet."
                    }
                    description={
                      d.value === "ingested"
                        ? "The documents and links this project works from."
                        : "The documents and links this project has made."
                    }
                  />
                ) : (
                  <List>
                    {rows.map((a) => (
                      <ArtifactRow
                        key={a.id}
                        artifact={a}
                        detaching={detachingId === a.id}
                        onDetach={() => void detach(a)}
                      />
                    ))}
                  </List>
                )}
              </div>
            );
          })
        )}
      </section>
    </div>
  );
}
