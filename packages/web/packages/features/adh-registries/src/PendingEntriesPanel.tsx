'use client';

import { useCallback, useState } from 'react';
import { useResourceList } from '@agentic-toolkit/data';
import { FieldGroup, SectionHeader } from '@agenticdevelopertoolkit/ui/blocks';
import { Button } from '@agenticdevelopertoolkit/ui/components/button';
import { ErrorText } from '@agenticdevelopertoolkit/ui/components/error-text';
import { Spinner } from '@agenticdevelopertoolkit/ui/components/spinner';
import type { EntryRow, EntryStatus, RegistryClient } from '@agentic-toolkit/registry/client';
import { registryEntriesKey, revalidateRegistryEntries } from './entriesCache';

export interface PendingEntriesPanelProps {
  /** The topic's own title, from the explorer's `titleFor` — same contract as every sibling panel. */
  title: string;
  registryId: string;
  client: RegistryClient;
}

/**
 * The two statuses a review decision may write. `Extract` rather than a bare
 * `'published' | 'draft'`, which was an unnamed inline subset of `EntryStatus` that nothing
 * checked against it: `Extract` is checked, so if `ENTRY_STATUSES` ever renames or drops one
 * of these, this type narrows and the `decide(entry, …)` call sites below stop compiling —
 * instead of this file quietly keeping a member the enum no longer has.
 *
 * Not `Exclude<EntryStatus, 'pending'>`, which reads more naturally and fails the wrong way:
 * renaming `pending` would silently make `pending` an acceptable decision.
 */
type Decision = Extract<EntryStatus, 'published' | 'draft'>;

/**
 * What each decision's button says, keyed by the status it writes. Record KEYS, not repeated
 * string literals at two call sites: `Record<Decision, …>` is exhaustive, so a status that
 * leaves the subset takes its button with it instead of leaving a control that PATCHes a value
 * the enum no longer has — and it makes the two buttons one piece of markup, since they
 * differed in nothing else.
 */
const ANSWER: Record<Decision, (name: string) => string> = {
  published: (name) => `Approve ${name}`,
  draft: (name) => `Send ${name} back`,
};

// Approve first — the queue's ordinary outcome, and the order these buttons have always
// rendered in. `Object.keys` on an object literal returns its string keys in declaration order,
// so the wording table above is also the ordering, with no second list to keep in step.
const DECISIONS = Object.keys(ANSWER) as Decision[];

/**
 * The owner's half of `submissionPolicy: 'reviewed'` — spec D11's "so an owner can gate
 * entries", and R4-C3.
 *
 * The builder has offered "Anyone, but I approve each one" since Task 5 and nothing anywhere
 * let the owner do the approving: a submission sat at `pending` indefinitely, the registrant's
 * own editor showed them "Draft", and the only way to discover any of it was a database query.
 * A gate the owner cannot open is unfinished spec work, not an omission to argue about.
 *
 * Approve and send back are the SAME PATCH the registrant's editor uses. That is deliberate
 * and is the backend's own decision, not this panel's shortcut: `assertEntryVerb` admits the
 * caller who authored the entry AND the one holding the sub-item verb on the parent registry,
 * and `resolveEntryStatus` keys its downgrade off the parent registry's owner — so the owner
 * asking for `published` is never re-gated to `pending` the way the registrant is. A dedicated
 * approve endpoint would have been a second copy of that policy.
 *
 * Mounted whatever the registry's current policy is, not only under `reviewed`: an owner who
 * switches back to `open` still has whatever was already pending, and a queue that vanishes
 * with the setting strands those submissions with no screen that can reach them.
 */
export function PendingEntriesPanel({ title, registryId, client }: PendingEntriesPanelProps) {
  const loadPending = useCallback(
    () => client.listEntries(registryId, 'pending').then((res) => res.items),
    [client, registryId],
  );
  // The queue rides the platform cache for the same reason the roster beside it does: an owner
  // moves between a registry's topics constantly, and this read used to start from nothing every
  // single time. `setItems` writes through the cache, so the row a decision takes off the queue
  // below stays off it after a navigation.
  const queueKey = registryEntriesKey(registryId, 'pending');
  const { items, error: loadError, setItems } = useResourceList(queueKey, loadPending);
  // A SET of entry ids, not one `busyId`, and `decide` adds its own key on entry and removes
  // its own key in `finally` — never `setBusyId(null)`, which lets one row's completion clear a
  // different row's flag when two decisions race. `EntryServicesPanel.tsx` states the same rule
  // over its own rows; a review queue is where an owner batch-clicks, so it is the surface most
  // likely to have two writes in flight. With a single flag, approving A then touching B
  // re-enables A's buttons while A's PATCH is still running, A's `finally` then clears B's flag,
  // and a second PATCH on A can land after the first — so the entry settles on `published` when
  // the owner's last instruction was `draft`.
  const [busy, setBusy] = useState<ReadonlySet<string>>(() => new Set());
  // Per row rather than one banner. `assertPublishable`'s 400 names the LABELS of the fields a
  // particular submission is still missing, and it is the only thing telling an owner why an
  // apparently-fine listing will not go live — beside the row it is about, or it is about
  // nothing.
  const [rowErrors, setRowErrors] = useState<Record<string, string>>({});

  async function decide(entry: EntryRow, status: Decision) {
    setBusy((cur) => new Set(cur).add(entry.id));
    setRowErrors(({ [entry.id]: _cleared, ...rest }) => rest);
    try {
      await client.updateEntry(registryId, entry.id, { status });
      // Off the queue because the server took it off: the row's status is no longer `pending`,
      // which is the only thing this list is. Refetching would be a second round trip to learn
      // what the PATCH just returned.
      setItems((current) => (current ?? []).filter((row) => row.id !== entry.id));
      // The ROSTER, though, cannot learn any of that from here: the same row is still on it and
      // its badge has just changed. Its own key is excluded — this queue is already correct, and
      // re-reading it is the round trip the line above exists to avoid.
      revalidateRegistryEntries(registryId, queueKey);
    } catch (e) {
      // Verbatim. Paraphrasing `assertPublishable` into "could not publish" would be this
      // panel deciding the owner does not need to know which fields are missing — which is
      // the entire content of the message.
      setRowErrors((current) => ({
        ...current,
        [entry.id]: e instanceof Error ? e.message : String(e),
      }));
    } finally {
      setBusy((cur) => {
        const next = new Set(cur);
        next.delete(entry.id);
        return next;
      });
    }
  }

  // Error only while there is nothing to show. The queue revalidates in the background — a
  // decision on any row sweeps it — and a failed background read used to replace an already
  // painted queue with a bare alert, taking away both the rows and the buttons that would have
  // retried. Once rows are on screen the failure renders as a line ABOVE them instead, which is
  // what the roster beside this already does.
  if (items === null) {
    return loadError ? (
      <ErrorText error={loadError} />
    ) : (
      <p className="flex items-center gap-2 text-sm text-apt-text-muted">
        <Spinner />
        Loading submissions…
      </p>
    );
  }

  // The platform's own vocabulary — `FieldGroup` per row, `Button` for the two decisions,
  // `ErrorText` for what `assertPublishable` says — for the same reason every other panel in
  // this feature uses it: a pane that renders bare `<ul>`/`<button>` is legible markup and is
  // not this product's UI, and the owner meets it in the same stack as Details and the
  // sections.
  return (
    <div className="flex flex-col gap-4">
      {/* The topic's own title, on BOTH branches. It used to be drawn by the empty state's own
          `FieldGroup`, so a queue with submissions in it — the state this pane exists for — had
          no heading at all, and each row's card was the first thing under the breadcrumb. */}
      <SectionHeader paneTitle title={title} />
      <ErrorText error={loadError} />
      {items.length === 0 ? (
        /* This list asks for `status=pending` only, so an empty answer says nothing about
           whether anyone has signed up — it says nobody is WAITING. Claiming the stronger thing
           sent owners looking for a bug in a registry whose providers were all approved. */
        <p className="text-sm text-apt-text-muted">
          Nothing is waiting for review. New submissions show up here.
        </p>
      ) : (
        items.map((entry) => {
          // The slug is the fallback for the same reason the section rail uses its key: a
          // nameless row is one the owner cannot tell apart from the next one.
          const name = entry.displayName || entry.slug;
          const rowBusy = busy.has(entry.id);
          return (
            <FieldGroup
              key={entry.id}
              title={name}
              trailing={
                <div className="flex items-center gap-2">
                  {DECISIONS.map((status) => (
                    <Button
                      key={status}
                      type="button"
                      size="sm"
                      variant={status === 'published' ? 'default' : 'ghost'}
                      disabled={rowBusy}
                      onClick={() => void decide(entry, status)}
                    >
                      {ANSWER[status](name)}
                    </Button>
                  ))}
                </div>
              }
            >
              {entry.summary ? (
                <p className="text-sm text-apt-text-muted">{entry.summary}</p>
              ) : null}
              {/* Beside the row it is about, never as a banner: `assertPublishable`'s 400 names
                  the LABELS of the fields THIS submission is still missing. */}
              <ErrorText error={rowErrors[entry.id] ?? null} />
            </FieldGroup>
          );
        })
      )}
    </div>
  );
}
