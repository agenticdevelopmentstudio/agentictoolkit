'use client';

import { useCallback, useState } from 'react';
import { Pencil, UserMinus } from 'lucide-react';
import { revalidateResourceItems, useResourceList } from '@agentic-toolkit/data';
import {
  type EntryRow,
  type EntryStatus,
  type ProviderType,
  type RegistryClient,
} from '@agentic-toolkit/registry/client';
import {
  EditableList,
  SectionHeader,
  useEditableList,
  type EditableListColumn,
  type EditableListFacet,
} from '@agenticdevelopertoolkit/ui/blocks';
import { AlertModal } from '@agenticdevelopertoolkit/ui/components/alert-modal';
import { Badge, type badgeVariants } from '@agenticdevelopertoolkit/ui/components/badge';
import { Button } from '@agenticdevelopertoolkit/ui/components/button';
import { ErrorText } from '@agenticdevelopertoolkit/ui/components/error-text';
import { formatDate } from '@agenticdevelopertoolkit/ui/lib/timestamps';
import type { VariantProps } from 'class-variance-authority';
import { EntryEditor } from './EntryEditor';
import {
  MY_ENTRY_CACHE_KEY,
  registryEntriesKey,
  revalidateRegistryEntries,
} from './entriesCache';
import { ProviderDetail } from './ProviderDetail';
import { useRegistryForm } from './useRegistryForm';

/**
 * Everyone who has signed up to this registry — the roster, in the shape every editable list
 * on adh takes (`EditableList`, the admin site's own).
 *
 * A "provider" is exactly a `registry.entries` row: the person or organization the signup form
 * produces, listed under their own profile. There is no separate table, and there was no screen
 * — an owner could see a submission while it sat in the review queue and then never again, so
 * "who is actually in my registry?" was a question the product could not answer.
 *
 * WHY THIS IS NOT THE SUBMISSIONS QUEUE, given both list entries. They are the same rows and
 * deliberately different surfaces, because they answer opposite questions and carry different
 * verbs. Submissions is a QUEUE — only `pending`, it empties, and its verbs are approve and send
 * back. This is the ROSTER — every status, it only grows, and its verb is removal. Folding the
 * queue in here would put a decision an owner must make behind a facet they have to know to set;
 * offering approve here as well would be the same policy written at two call sites, which is the
 * thing `PendingEntriesPanel` already refuses to do to the backend.
 *
 * Rows carry no buttons of their own — the bar acts on the selection — which is `EditableList`'s
 * model and not a local choice: a per-row Remove and a bar Remove are one action offered twice
 * with different reach.
 *
 * Under the table sits the selected provider's PROFILE, in a pane the owner can drag taller
 * (`EditableList`'s `details`). Six columns are the answer to "who is in here?"; the pane is the
 * answer to "who is this one?" — and its Edit opens the registrant's own editor over that
 * entry, so an owner fixing a listing and the registrant who wrote it are filling in the same
 * form.
 */

type BadgeVariant = NonNullable<VariantProps<typeof badgeVariants>['variant']>;

/**
 * What each status says on the roster, and in what tone.
 *
 * Keyed by `EntryStatus`, so a status added to the enum is a compile error here rather than a
 * row that renders a raw `draft`-shaped token. The words are the ones the two people involved
 * have already been shown: the registrant's own editor says "Draft", the queue calls a pending
 * row a submission, and a live listing is "Published" everywhere it appears publicly.
 */
const STATUS: Record<EntryStatus, { label: string; variant: BadgeVariant }> = {
  published: { label: 'Listed', variant: 'success' },
  pending: { label: 'Submitted', variant: 'accent' },
  draft: { label: 'Draft', variant: 'neutral' },
};

/** `ProviderType` in the owner's words — what the listing is ABOUT, not who signed in. */
const TYPE: Record<ProviderType, string> = {
  person: 'Person',
  organization: 'Organization',
  persona: 'Persona',
};

/**
 * The two token→word lookups, as TOTAL functions.
 *
 * Both maps are `Record<Union, …>`, so TypeScript says the lookup cannot miss — but the rows are
 * JSON off the wire, cast into that union and never checked against it. The day the backend
 * gains a fourth status (`archived`, `rejected`), every row carrying it reads `undefined.label`
 * and the WHOLE roster goes blank: the owner loses the list of everyone in their registry
 * because one row has a word this file has not learned yet. The raw token is a poor label and a
 * perfectly good answer, and it is the one the facet filter already falls back to — stated once
 * here so the column, the badge and the filter cannot disagree about what an unknown means.
 */
function statusOf(status: string): { label: string; variant: BadgeVariant } {
  return STATUS[status as EntryStatus] ?? { label: status, variant: 'neutral' };
}
function typeOf(providerType: string): string {
  return TYPE[providerType as ProviderType] ?? providerType;
}

export interface RegistryProvidersPanelProps {
  /** The topic's own title, from the explorer's `titleFor` — same contract as every sibling. */
  title: string;
  registryId: string;
  client: RegistryClient;
}

export function RegistryProvidersPanel({
  title,
  registryId,
  client,
}: RegistryProvidersPanelProps) {
  const [confirming, setConfirming] = useState(false);
  const [removing, setRemoving] = useState(false);
  const [removeError, setRemoveError] = useState<string | null>(null);
  /** The provider whose profile the owner opened for editing, or `null` — the roster. */
  const [editingId, setEditingId] = useState<string | null>(null);

  // No `status` argument: every status, which is what makes this the roster rather than a second
  // copy of the queue.
  const loadRoster = useCallback(
    () => client.listEntries(registryId).then((res) => res.items),
    [client, registryId],
  );
  // Through the platform cache, like every other list on the hub. It used to be a `useEffect`
  // whose only memory was this component's state, so leaving the roster for Details and coming
  // back re-fetched it cold every time; now it paints from the cache and revalidates behind that.
  // `items` keeps the meaning it had — `null` is "still loading" and `[]` is "loaded, nobody
  // here", the distinction the empty state depends on and the same one `PendingEntriesPanel`
  // draws beside it — and `setItems` writes THROUGH the cache, so the optimistic removal below
  // survives the next visit instead of being undone by it.
  const rosterKey = registryEntriesKey(registryId);
  const { items, error: loadError, setItems } = useResourceList(rosterKey, loadRoster);

  // Loaded WITH the roster rather than on the Edit press, because it is the same cached entry
  // the registrant's own editor fills and it is what makes Edit open instantly instead of
  // spending a round trip after the click — the whole point of putting these reads through the
  // cache in the first place.
  const { form, error: formError } = useRegistryForm(registryId, client);

  const columns: EditableListColumn<EntryRow>[] = [
    {
      key: 'name',
      header: 'Provider',
      // The slug is the fallback for the same reason the queue uses it: a nameless row is one
      // the owner cannot tell from the next one.
      value: (row) => row.displayName || row.slug,
      render: (row) => (
        <span className="flex items-center gap-2">
          <span className="flex size-5 shrink-0 items-center justify-center rounded-full bg-apt-surface-2 text-[10px] font-medium text-apt-text-muted">
            {(row.displayName || row.slug).charAt(0).toUpperCase()}
          </span>
          <span className="truncate font-medium text-apt-text">
            {row.displayName || row.slug}
          </span>
        </span>
      ),
    },
    {
      key: 'address',
      header: 'Address',
      value: (row) => row.slug,
      render: (row) => <span className="font-mono text-xs text-apt-text-muted">{row.slug}</span>,
    },
    {
      key: 'type',
      header: 'Type',
      width: '9rem',
      value: (row) => typeOf(row.providerType),
      render: (row) => <Badge>{typeOf(row.providerType)}</Badge>,
    },
    {
      key: 'location',
      header: 'Location',
      value: (row) => row.locationText,
    },
    {
      key: 'status',
      header: 'Status',
      width: '8rem',
      // Sorted and searched by the WORD the owner reads, not by the stored token — otherwise
      // typing "listed" in the filter box matches nothing on screen.
      value: (row) => statusOf(row.status).label,
      render: (row) => (
        <Badge variant={statusOf(row.status).variant}>{statusOf(row.status).label}</Badge>
      ),
    },
    {
      key: 'signedUp',
      header: 'Signed up',
      width: '9rem',
      // Sorted by the RAW timestamp and rendered as a date: sorting by the rendered value
      // would order the roster lexically by a localised string.
      value: (row) => row.createdAt,
      render: (row) => (
        <span className="text-xs text-apt-text-muted">{formatDate(row.createdAt)}</span>
      ),
    },
  ];

  const facets: EditableListFacet<EntryRow>[] = [
    {
      id: 'status',
      label: 'Status',
      valuesOf: (row) => [row.status],
      labelOf: (value) => statusOf(value).label,
    },
    {
      id: 'type',
      label: 'Type',
      valuesOf: (row) => [row.providerType],
      labelOf: typeOf,
    },
  ];

  const list = useEditableList<EntryRow>({
    rows: items ?? undefined,
    getRowId: (row) => row.id,
    columns,
    facets,
    // The server already returns newest first, so this changes no row's position — it names
    // the order the arrow is already in, which is what makes it reversible.
    initialSort: { key: 'signedUp', dir: 'desc' },
  });

  const selected = list.selectedRows;
  // Read out of the roster, never held as its own copy: a row removed (here or in the queue)
  // takes its editor with it, instead of leaving one open over an entry that is gone.
  const editing = editingId ? (items ?? []).find((row) => row.id === editingId) ?? null : null;

  async function removeSelected() {
    setRemoving(true);
    setRemoveError(null);
    const gone = new Set<string>();
    const failures: string[] = [];
    // Sequential, not `Promise.all`: each failure has to be attributable to the row it came
    // from — the backend's 403/404 says nothing about which entry it was about — and a bulk
    // remove is the one gesture where an owner most needs to know exactly what survived.
    for (const row of selected) {
      try {
        await client.deleteEntry(registryId, row.id);
        gone.add(row.id);
      } catch (e) {
        failures.push(`${row.displayName || row.slug}: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
    setItems((current) => (current ?? []).filter((row) => !gone.has(row.id)));
    // A removed entry is gone from the review queue too, which is a different cache entry and
    // cannot learn that from this one. Not the roster's own key: it has just been written above.
    if (gone.size > 0) revalidateRegistryEntries(registryId, rosterKey);
    // Whatever failed STAYS selected, so the retry is one press rather than a re-tick of the
    // rows that did not go — and so the count in the bar is the count the button will act on.
    list.setSelectedIds(new Set(selected.filter((row) => !gone.has(row.id)).map((row) => row.id)));
    setRemoving(false);
    setConfirming(false);
    if (failures.length > 0) setRemoveError(failures.join('; '));
  }

  // The owner editing somebody else's listing gets the REGISTRANT'S editor, not a second one.
  // `EntryEditor` already takes the entry as a prop and saves through `updateEntry`, which the
  // backend does not re-gate to the entry's author — so the only thing an owner-specific editor
  // would add is a second place for the same form to drift. It publishes its own rail level, so
  // the sections appear as the next level of the stack rather than as a navigator bolted into
  // this pane, and its Cancel bar sits above the leaf whether or not a section is open.
  if (editing) {
    if (!form) {
      return formError ? (
        <ErrorText error={formError} />
      ) : (
        <p className="text-sm text-apt-text-muted">Loading the signup form…</p>
      );
    }
    return (
      <EntryEditor
        // Remounted per provider: `useDirtyDraft` seeds once and never re-seeds, so without a
        // key a second Edit would open the first provider's draft under the second one's name.
        key={editing.id}
        registryId={registryId}
        entry={editing}
        sections={form.sections}
        fieldDefs={form.fieldDefs}
        entryTerm={form.entryTerm}
        categoryRoot={form.categoryRoot}
        servicesEnabled={form.servicesEnabled}
        boundSiteId={form.boundSiteId}
        client={client}
        onCancel={() => setEditingId(null)}
        onSaved={(saved) => {
          // Straight into the roster, so the row behind the editor already shows the new name
          // when the owner closes it — and through `setItems`, so the cache holds it too.
          setItems((current) => (current ?? []).map((row) => (row.id === saved.id ? saved : row)));
          // The review queue lists the same row and cannot learn from here that it changed.
          // Not the roster's own key: it has just been written above.
          revalidateRegistryEntries(registryId, rosterKey);
          // And the REGISTRANT holds their own copy of this very row, in a different cached
          // collection (`registry-my-entry`, one item per registry) that no sweep of the entry
          // LISTS can reach. Without this, a correction the owner makes here is invisible in the
          // registrant's own editor for the cache's full life — and their next save writes their
          // stale copy straight back over it. Matched on the collection because the id there is
          // the REGISTRY's, not the entry's, so the row that changed does not name the key.
          revalidateResourceItems((key) => key === MY_ENTRY_CACHE_KEY);
        }}
      />
    );
  }

  return (
    <div className="flex flex-col gap-3">
      {/* The platform's own content header — the same one every /home pane is titled by —
          rather than a bare heading. `FieldGroup` is the wrong wrapper here: it is a bordered
          card, and `EditableList` already draws its own bar and table border inside one. */}
      <SectionHeader paneTitle title={title} />

      {/* The bulk remove's own failure, NOT `EditableList`'s `error` — that one is the LOAD's,
          and it renders "showing the last rows that loaded", which says the wrong thing about
          a delete that came back 403. */}
      <ErrorText error={removeError} />

      <EditableList<EntryRow>
        list={list}
        ariaLabel="Providers"
        loading={items === null}
        error={loadError}
        errorTitle="Couldn't load this registry's providers"
        columnWidthsKey="registry-providers"
        searchPlaceholder="Filter providers"
        describeRow={(row) => row.displayName || row.slug}
        emptyLabel="Nobody has signed up to this registry yet."
        emptyFilteredLabel="No providers match these filters."
        // The profile under the roster, for the ONE provider the owner has picked. Edit lives on
        // the pane's own bar rather than in the row or the top bar: it acts on exactly the record
        // the pane is showing, which is the case the no-buttons-on-rows rule already excepts, and
        // it means the verb sits next to the thing it edits.
        details={{
          label: 'Profile',
          storageKey: 'registry-providers-details',
          render: (row) => <ProviderDetail entry={row} />,
          emptyLabel: 'Select a provider to see their profile.',
          manyLabel: 'Select a single provider to see their profile.',
          actions: (row) => (
            <Button
              variant="ghost"
              size="sm"
              disabled={row === null}
              onClick={() => row && setEditingId(row.id)}
            >
              <Pencil data-icon="inline-start" />
              Edit
            </Button>
          ),
        }}
        actions={
          <Button
            variant="ghost"
            size="sm"
            disabled={selected.length === 0 || removing}
            onClick={() => setConfirming(true)}
          >
            <UserMinus data-icon="inline-start" />
            Remove
          </Button>
        }
      />

      {/*
        A confirm naming the count, not a typed confirmation. The typed kind is for destroying
        something the owner cannot rebuild — the registry itself, in `RegistryDetailsPanel` —
        and here the registrant still has their account and can sign up again, which is exactly
        what the freed slug is for.
      */}
      <AlertModal
        open={confirming}
        destructive
        busy={removing}
        title={
          selected.length === 1
            ? `Remove ${selected[0]!.displayName || selected[0]!.slug} from the registry?`
            : `Remove ${selected.length} providers from the registry?`
        }
        description="Their listing stops appearing, and the address it was published at is freed for a new signup. Nothing here puts it back."
        confirmLabel="Remove"
        cancelLabel="Cancel"
        onConfirm={() => void removeSelected()}
        onCancel={() => setConfirming(false)}
      />
    </div>
  );
}
