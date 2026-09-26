"use client";

import { useMemo, useState } from "react";
import { CircleCheck, KeyRound, Lock, TriangleAlert } from "lucide-react";
import {
  useReleaseReservedIdentifier,
  useReservedIdentifiers,
  type ReleaseResult,
  type ReservedIdentifier,
} from "../api/reserved-identifiers";
import {
  REASONS,
  rdidType,
  releaseExplanation,
  releaseRunSummary,
} from "../lib/reserved-identifiers-copy";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Alert, AlertDescription, AlertTitle } from "@agenticdevelopertoolkit/ui/components/alert";
import { errorMessage } from "@agenticdevelopertoolkit/ui/lib/errors";
import { ApiButton } from "@agentic-toolkit/api-explorer";
import {
  EditableList,
  TypeToConfirmDialog,
  useEditableList,
  type EditableListColumn,
} from "../components/editable-list";
import { formatDate } from "../lib/timestamps";

/**
 * Reserved Identifiers — names that are TAKEN with nothing using them, and the bar that gives them
 * back.
 *
 * The three reasons are shown rather than collapsed into "unused", because they answer different
 * questions for an operator and, more practically, because releasing them does different things:
 * two delete a mapping, and the third RENAMES a dead row so its real name returns to the pool. The
 * wording that carries that distinction lives in src/lib/reserved-identifiers-copy.ts, where it can
 * be asserted.
 */

/** The row identity used by the table AND by the release queue, so the two cannot disagree. */
const rowId = (item: ReservedIdentifier) => `${item.entityType}/${item.entityId}/${item.rdid}`;

export function ReservedIdentifiersPane() {
  const [results, setResults] = useState<{
    freed: ReleaseResult[];
    skipped: string[];
  } | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  /**
   * The names this run still has to release, and how far through it is.
   *
   * A release run is a QUEUE rather than one bulk call because each name is confirmed by typing
   * it: the point of the gate is that the operator reads the name they are about to free, and one
   * dialog covering six of them reads exactly one. So the dialog stays open and walks the
   * selection, and `done` is what has already been freed — a run abandoned halfway still reports
   * what it did, because those names really are gone.
   */
  const [queue, setQueue] = useState<ReservedIdentifier[] | null>(null);
  const [done, setDone] = useState<ReleaseResult[]>([]);
  /**
   * How far through the queue the dialog is — an explicit cursor, NOT `done.length`.
   *
   * Derived from the successes, the run could only ever move forwards by succeeding: a name that
   * 409s (a parent released before its children does exactly that, and so does a name whose entity
   * has changed under it) left the dialog re-presenting the same doomed item indefinitely, with
   * Cancel — which throws away every item behind it — as the only way out. The cursor is what lets
   * Skip exist.
   */
  const [cursor, setCursor] = useState(0);
  /** Names the run stepped OVER. Still held, and named in the summary so they are not lost. */
  const [skipped, setSkipped] = useState<string[]>([]);

  const { data, isLoading, error } = useReservedIdentifiers();
  const release = useReleaseReservedIdentifier();

  const columns: EditableListColumn<ReservedIdentifier>[] = useMemo(
    () => [
      {
        key: "rdid",
        header: "Identifier",
        value: (item) => item.rdid,
        render: (item) => (
          <span className="flex items-center gap-1.5">
            {/* A row the backend will not release says so HERE rather than in a column of its
                own: `releasable` is a property of the name, it is true of almost every row, and
                a whole column to carry one glyph is a column of blanks. The Release button
                refuses these too — the glyph is why, not the enforcement. */}
            {!item.releasable && (
              <Lock
                className="size-3 shrink-0 text-apt-text-dim"
                aria-label="Reserved by policy"
              />
            )}
            <span className="truncate font-mono text-xs text-apt-text">{item.rdid}</span>
          </span>
        ),
      },
      {
        key: "type",
        header: "Type",
        width: "8rem",
        value: (item) => rdidType(item.rdid),
      },
      {
        key: "reason",
        header: "Reason",
        width: "8rem",
        value: (item) => REASONS[item.reason].label,
        render: (item) => (
          <Badge variant={REASONS[item.reason].variant} title={REASONS[item.reason].blurb}>
            {REASONS[item.reason].label}
          </Badge>
        ),
      },
      {
        key: "heldSince",
        header: "Held since",
        width: "9rem",
        // Sorted by the RAW timestamp, shown formatted: sorting by "22 Aug 2026" is sorting
        // alphabetically by month name.
        value: (item) => item.heldSince ?? "",
        render: (item) => (
          <span className="text-xs text-apt-text-dim">{formatDate(item.heldSince)}</span>
        ),
      },
    ],
    [],
  );

  const list = useEditableList<ReservedIdentifier>({
    rows: data?.items,
    getRowId: rowId,
    columns,
    facets: [
      {
        id: "type",
        label: "Type",
        // The rdid's own prefix, not `entityType`: `storage` is the word in the name the operator
        // is looking at, and `bucket` is the word in the table behind it.
        valuesOf: (item) => [rdidType(item.rdid)],
      },
      {
        id: "reason",
        label: "Reason",
        valuesOf: (item) => [item.reason],
        labelOf: (value) => REASONS[value as keyof typeof REASONS]?.label ?? value,
      },
    ],
    initialSort: { key: "heldSince", dir: "desc" },
  });

  // Only the ones a release can actually act on. A selection that includes a policy-reserved name
  // is not an error — the operator ticked a range — but the run must not stop on it.
  const releasable = list.selectedRows.filter((item) => item.releasable);
  const current = queue?.[cursor] ?? null;

  function startRun(): void {
    setFailure(null);
    setResults(null);
    setDone([]);
    setSkipped([]);
    setCursor(0);
    setQueue(releasable);
  }

  /** One step forward, and the end of the run when there is nothing left to step to. */
  function advance(freed: ReleaseResult[], stepped: string[]): void {
    setFailure(null);
    if (queue && cursor + 1 >= queue.length) return finish(freed, stepped);
    setDone(freed);
    setSkipped(stepped);
    setCursor(cursor + 1);
  }

  function finish(freed: ReleaseResult[], stepped: string[]): void {
    setQueue(null);
    setDone([]);
    setSkipped([]);
    setCursor(0);
    setFailure(null);
    if (freed.length > 0 || stepped.length > 0) {
      setResults({ freed, skipped: stepped });
      // The released rows are gone from the list, so the selection they were in describes nothing.
      if (freed.length > 0) list.clearSelection();
    }
  }

  return (
    <div>
      <div className="mb-6 flex items-center justify-between gap-2">
        <h1 className="text-2xl font-bold text-apt-text">Reserved Identifiers</h1>
        <ApiButton
          endpoint={{ method: "GET", path: "/system/reserved-identifiers" }}
          title="Reserved Identifiers API"
        />
      </div>

      <p className="mb-4 max-w-3xl text-sm text-apt-text-muted">
        Names nothing is using but that can&apos;t be taken again — left over from a rename, pointing
        at something that no longer exists, or still held by something deleted. Releasing one puts it
        back in the pool, along with any held name underneath it.
      </p>

      {failure && (
        <Alert variant="error" className="mb-6">
          <TriangleAlert />
          <AlertTitle>Couldn&apos;t release the name</AlertTitle>
          <AlertDescription>{failure}</AlertDescription>
        </Alert>
      )}

      {/* A release that only PARTLY worked reports as a warning, not a success: `stillHeldBy` names
          live addresses the cascade refused to move, and an operator who reads "released" and walks
          away would find the name still taken. */}
      {results && <RunOutcome results={results.freed} skipped={results.skipped} />}

      <EditableList
        list={list}
        ariaLabel="Reserved identifiers"
        loading={isLoading}
        error={error}
        errorTitle="Couldn't load reserved identifiers"
        // The backend's scans are capped, and the filtering above them is client-side — so a name
        // beyond the cap answers a search with an empty table, which on THIS surface reads as
        // "free to use". Said out loud, with the number, so the operator can tell the two apart.
        truncationNotice={
          data?.truncated ? (
            <>
              Showing {data.total.toLocaleString()} held names, and there are more than this page
              fetches. <strong>A name missing from this table may still be held</strong> — an empty
              result here is not proof that a name is free.
            </>
          ) : undefined
        }
        columnWidthsKey="admin-reserved-identifiers"
        // The rdid is the name the operator is looking at; the row id is a composite of three
        // fields and names nothing. Without this the checkbox would fall back to `entityType` and
        // every held bucket on the page would read "Select bucket".
        describeRow={(item) => item.rdid}
        searchPlaceholder="Filter identifiers"
        emptyLabel="Nothing is being held."
        emptyFilteredLabel="No held names match these filters."
        actions={
          <Button
            size="sm"
            variant="destructive-ghost"
            disabled={releasable.length === 0}
            onClick={startRun}
          >
            <KeyRound data-icon="inline-start" />
            Release
            {releasable.length > 0 ? ` (${releasable.length})` : ""}
          </Button>
        }
      />

      <TypeToConfirmDialog
        open={current !== null}
        title={
          queue && queue.length > 1
            ? `Release name ${cursor + 1} of ${queue.length}`
            : "Release this name?"
        }
        description={current ? releaseExplanation(current) : undefined}
        confirmValue={current?.rdid ?? ""}
        valueNoun="name"
        confirmLabel="Release"
        busy={release.isPending}
        error={failure}
        onCancel={() => finish(done, skipped)}
        // Only while there is somewhere to skip TO. On a one-name run the two buttons would be
        // Cancel and Cancel.
        onSkip={
          queue && queue.length > 1 && current
            ? () => advance(done, [...skipped, current.rdid])
            : undefined
        }
        skipLabel="Skip this one"
        onConfirm={() => {
          if (!current) return;
          setFailure(null);
          release.mutate(current, {
            onSuccess: (result) => advance([...done, result], skipped),
            onError: (e) => setFailure(errorMessage(e)),
          });
        }}
      />
    </div>
  );
}

/** The summary a finished run leaves behind — one alert for the whole selection, not one per name. */
function RunOutcome({ results, skipped }: { results: ReleaseResult[]; skipped: string[] }) {
  const { title, detail } = releaseRunSummary(results, skipped);
  const clean = skipped.length === 0 && results.every((r) => r.freed);
  return (
    <Alert variant={clean ? "success" : "accent"} className="mb-6">
      {clean ? <CircleCheck /> : <TriangleAlert />}
      <AlertTitle>{title}</AlertTitle>
      <AlertDescription>{detail}</AlertDescription>
    </Alert>
  );
}
