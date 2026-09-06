'use client';

import * as React from 'react';

import { ErrorText } from '@agenticdevelopertoolkit/ui/components/error-text';
import { Spinner } from '@agenticdevelopertoolkit/ui/components/spinner';

import type { ShiprClient } from './client';
import { stampMs } from './freshness';
import { Ladder } from './ladder/Ladder';
import { repoLabel } from './tree/toLevels';
import { RepoReport } from './report/RepoReport';
import { TERMINAL_STATES, type RepoDetail } from './types';

/**
 * ONE REPOSITORY, THE WHOLE ANSWER — and the ONLY place this console draws one.
 *
 * Name, ladder, latest output, in that order. It is mounted twice: alone, as the pane of a
 * repository picked in the rail, and once per repository stacked under a folder. There is no
 * second, smaller rendering for the folder case, and that is exactly the point — the folder
 * pane used to draw its own heading over a bare report, so the same repository looked like
 * two different facts depending on which row was highlighted. One whose latest run was a
 * folder-wide one showed "this run produced no output here" and NOTHING else, while the pane
 * one click away showed its whole pipeline in colour. Same component, same fetch, everywhere.
 *
 * The LADDER IS THE ANSWER and it goes first, with the latest run's output beneath it. The
 * two answer the two halves of the same question — where the pipeline IS, and what the last
 * thing to move it said — and they used to be a column apart, the ladder in this pane and
 * the output in an activity log that showed whichever run was most recent anywhere on the
 * screen. Now they are the same section, about the same repository, in that order.
 *
 * THE TIMESTAMP IS THE HEADING'S, not the log's. When the last run finished is the first
 * thing a stack of these is read for, so it rides the right edge of the row that names the
 * repository — one column of times down the page, scannable, instead of a sub-line whose
 * left edge moves with whatever the run happened to be called.
 *
 * The names underneath (which branch is `ship`, which CI context is watched) are NOT here.
 * They are reference material, consulted when the ladder shows something surprising, and
 * they sat between the operator and the output the whole rest of the time; they live behind
 * the rail's Settings item now.
 *
 * A repository that has never had `status` run against it has NO ladder at all — the route
 * answers `null`, not an empty one — and the view says so and says to run it. THIS VIEW
 * still fires nothing itself: it is mounted once per repository inside a folder's stack, so
 * a read started here would be forty of them the moment a folder is opened. Opening ONE
 * repository does now read it, at most once an hour, and the console owns that because the
 * console is the thing that knows a single row was clicked — see `statusIsStale` and the
 * effect that uses it in `ShiprConsole`.
 *
 * The two absences are kept apart on purpose. `null` is "nobody has looked"; a ladder with
 * no rows is "we looked, and there is nothing" — and only the second one is a statement
 * about the repository. Collapsing them would let a view nobody has refreshed read as a
 * pipeline with no history.
 */

export interface RepoViewProps {
  client: ShiprClient;
  repoId: string;
  /**
   * The sub-folders between the folder being listed and this repository — `''` for one filed
   * directly in it.
   *
   * UNDEFINED is a different thing from `''`: it means this view is standing alone as a pane
   * of its own rather than as one section of a folder's stack. Alone it heads the pane and
   * names the folder it is in; in a stack the enclosing pane has already said both, so it
   * names its path instead and steps down a heading level.
   */
  relativePath?: string;
  /** Refresh token — bump it and the view re-reads (after a run, after a move). */
  nonce?: number;
  /**
   * Is the runner inside THIS repository right now?
   *
   * A folder-wide run is one queued entry, so a pane that only re-read when the entry
   * finished showed forty stale ladders while the runner walked them and then rewrote all
   * forty at once (Mike: "we need to finish each repo one at a time ... update the status
   * dot before moving onto the next repo"). Each section watches its own turn instead: the
   * flag going true is the runner arriving, going false is the verdict landing, and both
   * edges re-read this section ALONE. That is two reads per repository across a batch, where
   * a shared counter ticking per step would have been one read per repository per step.
   */
  running?: boolean;
  /**
   * Follow the output as it arrives. On when this view is the only thing on the screen; off
   * inside a folder's stack, where a page that scrolls to whichever of forty sections wrote
   * last cannot be read at all.
   */
  follow?: boolean;
  onSelectCommit?: (sha: string) => void;
  className?: string;
}

interface State {
  detail: RepoDetail | null;
  loading: boolean;
  error: string | null;
}

export function useRepoDetail(
  client: ShiprClient,
  repoId: string | null,
  nonce = 0,
): State {
  const [state, setState] = React.useState<State>({
    detail: null,
    loading: false,
    error: null,
  });
  const clientRef = React.useRef(client);
  clientRef.current = client;

  React.useEffect(() => {
    if (!repoId) {
      setState({ detail: null, loading: false, error: null });
      return;
    }
    let closed = false;
    setState((prev) => ({ ...prev, loading: true }));
    void (async () => {
      try {
        const detail = await clientRef.current.repo(repoId);
        if (!closed) setState({ detail, loading: false, error: null });
      } catch (e) {
        if (!closed)
          setState({
            detail: null,
            loading: false,
            error: (e as Error).message,
          });
      }
    })();
    return () => {
      closed = true;
    };
  }, [repoId, nonce]);

  return state;
}

export function RepoView({
  client,
  repoId,
  relativePath,
  nonce = 0,
  running = false,
  follow = false,
  onSelectCommit,
  className,
}: RepoViewProps): React.ReactElement {
  // This section's own turns, counted, and added to whatever the pane asked for — see
  // `running`. A count and not the flag itself because the read has to happen on BOTH edges,
  // and a boolean handed to an effect that runs on change cannot say which edge it was.
  const [selfReads, setSelfReads] = React.useState(0);
  const wasRunning = React.useRef(running);
  React.useEffect(() => {
    if (wasRunning.current === running) return;
    wasRunning.current = running;
    setSelfReads((n) => n + 1);
  }, [running]);
  const reads = nonce + selfReads;

  const { detail, loading, error } = useRepoDetail(client, repoId, reads);
  const alone = relativePath === undefined;

  if (error) {
    return (
      <div className={className}>
        <ErrorText error={error} className="p-4" />
      </div>
    );
  }
  if (!detail) {
    return (
      <div
        className={`flex items-center gap-2 p-4 text-sm text-apt-text-muted ${className ?? ''}`}
      >
        <Spinner /> Reading the repository…
      </div>
    );
  }

  const { repo, devRepo, group, ladder } = detail;
  // The last `status` run is what the ladder was read from, and a ladder with no timestamp
  // is a ladder nobody has refreshed — say so rather than presenting old rows as current.
  // `runs` is newest-first and the report below takes its head, so this is provably the same
  // run the output belongs to — read once here, for the heading's right-hand column.
  const latest = detail.runs[0] ?? null;

  /**
   * IS THE LADDER BELOW FROM BEFORE THE BUTTON WAS PRESSED?
   *
   * `pressed` remounts this pane the instant a control is used, so the previous run's ladder
   * and log go immediately — and then the re-read handed the SAME rows straight back,
   * because `repo_states` still held what the last `status` saw. The pane blinked and looked
   * exactly as it had (Mike: "when pressing a button the display should clear").
   *
   * The ladder is DATED, so the question has an answer: a run created after that read has
   * not spoken for this repository yet. Per repository and not per run — a status over a
   * folder of forty writes each read as it reaches it, so the sections fill in one at a time
   * behind the walking runner instead of all of them at the end.
   *
   * `prepare` and `deploy` do not write a read, only invalidate one, so their sections stay
   * cleared until the run is over. That is the honest answer for them: a branch has just
   * moved and nothing has looked since.
   *
   * Written as a negated `>=` on purpose: an absent or unparseable stamp is `NaN`, every
   * comparison against it is false, and the section that has never been read must clear.
   */
  const pending =
    latest !== null &&
    !TERMINAL_STATES.includes(latest.state) &&
    !(stampMs(ladder?.readAt) >= stampMs(latest.createdAt));

  return (
    <section className={`flex min-h-0 min-w-0 flex-col ${className ?? ''}`}>
      {/* NO RULE UNDER THE NAME (Mike). The heading and the ladder beneath it are one
          object — a repository and where its branches are standing — and a line between
          them cuts that object in half, so the name reads as a caption on a separate
          panel. The lines that DO belong are the ones between repositories, drawn by the
          stack in `GroupDetailPane`; spacing does the rest of the work here. */}
      <header className="flex shrink-0 flex-wrap items-baseline gap-x-3 gap-y-1 px-4 pb-1 pt-3">
        {React.createElement(
          alone ? 'h2' : 'h3',
          { className: 'text-sm font-semibold text-apt-text' },
          relativePath ? (
            // Two repositories called `web` in two sub-folders are one word apart, and the
            // word is the sub-folder — dimmed, because it is the qualifier and not the name.
            <span key="path" className="font-normal text-apt-text-muted">
              {relativePath}/
            </span>
          ) : null,
          // ONE NAME, THE CONFIGURED ONE (Mike). The heading used to read
          // `owner/name` plus a gold shard beside it — three tokens for one thing, none of
          // them the name anybody chose. `repoLabel` is the single answer the rail already
          // gives, so the pane and the row it was opened from now agree letter for letter.
          // The full `owner/name` has not gone anywhere: it is the first line of the facts
          // block below, where a reference belongs.
          repoLabel({ slug: repo.slug, devRepo }),
        )}
        {alone && group ? (
          // `name`, NEVER `path` — `path` is the backend's id ancestry, a key for prefix
          // matching an index, and rendering it puts a row of uuids where a folder name
          // belongs. The rail above already shows the full trail, so the name is the whole
          // answer here. Inside a folder's stack it is dropped: every section in that stack
          // is in the same folder, and the pane's own heading has just named it.
          <span className="text-xs text-apt-text-muted">in {group.name}</span>
        ) : null}
        {loading ? <Spinner /> : null}
        {/* `ml-auto`: the right edge, on the SAME baseline as the name — the one column a
            reader scans a stack of these down. */}
        {latest?.finishedAt ? (
          <span className="ml-auto font-mono text-xs text-apt-text-muted">
            {latest.finishedAt}
          </span>
        ) : null}
      </header>

      {/* THE COMMITS SIT DIRECTLY UNDER THE NAME (Mike). The heading's `pb-3` and this
          block's `pt-3` used to stack into a full blank line between a repository's name and
          the first thing it says, which down a folder of six reads as six unrelated panels
          rather than six entries in one list. The name and its ladder are one object; the gap
          that matters is the one BELOW, separating this repository from the next. */}
      {/* NOTHING HERE WHILE SOMETHING IS COMING — see `pending`. Deliberately not a
          placeholder: the report below is already saying it is waiting, and a second
          message in the ladder's place is two lines of furniture per repository down a
          folder of forty. */}
      {pending ? null : (
        <div className="shrink-0 px-2 pb-3">
          {ladder ? (
            <Ladder ladder={ladder} onSelectCommit={onSelectCommit} />
          ) : (
            <p className="px-2 py-6 text-sm text-apt-text-muted">
              Never read — run <span className="font-mono">status</span>{' '}
              to see where this repository&rsquo;s branches are standing.
            </p>
          )}
        </div>
      )}

      {/* The output the ladder came from. `knownRuns` is handed down so the report does not
          re-read the document this view has already got. */}
      <RepoReport
        client={client}
        repoId={repo.id}
        knownRuns={detail.runs}
        nonce={reads}
        follow={follow}
        className={
          alone ? 'min-h-0 flex-1 border-t border-apt-border' : 'shrink-0 pb-2'
        }
      />
    </section>
  );
}
