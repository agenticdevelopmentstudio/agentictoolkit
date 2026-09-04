"use client";

import { useEffect, useRef, useState, type KeyboardEvent, type ReactElement } from "react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Alert } from "@agenticdevelopertoolkit/ui/components/alert";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import type { MaskedProviderConfig, ProviderCatalogEntry } from "@agentic-toolkit/data/integrations";
import { intBlank, type IntegrationInput } from "./IntegrationDetail";
import { IntegrationDetailBody, useIntegrationSubmit } from "./IntegrationDetailView";
import { clearDraft, listDrafts, loadDraft, saveDraft } from "./integration-draft-store";

/**
 * ADDING AN INTEGRATION IS TWO DIALOGS, not one two-pane screen.
 *
 * It used to be a single 85vh modal with a filter list down the left and a whole provider form
 * — three cards, every field, its own Add button — inflated down the right. That shape had four
 * problems and they compound: the dialog was enormous whether or not anything was selected; the
 * list rows carried a name and a one-word subtitle, so a picker whose entire job is "which of
 * these do I want" said almost nothing about any of them; filtering changed the list's height,
 * which resized the dialog under the cursor mid-keystroke; and the Add button lived at the
 * bottom of a scrolling column, where Enter could not reach it and no Cancel sat beside it.
 *
 * So the two questions are asked in two dialogs. THIS one is the picker: a fixed-height list of
 * services, each with the catalog's own description, driven from the keyboard (type to filter,
 * arrows to move, Enter to choose) with OK/Cancel in the footer. Choosing one opens
 * {@link ConfigureProviderDialog} over it — a small dialog about exactly that service, with its
 * fields, and with OK and Cancel in the footer where Enter and Escape reach them.
 *
 * The height is FIXED (`h-[32rem]`), and that is the point rather than a style choice: the list
 * scrolls inside it, so a filter that narrows twelve services to one leaves the frame exactly
 * where it was. A dialog that resizes while you type moves the thing you are aiming at.
 *
 * Drafts are unchanged: a per-provider draft is persisted (secrets stripped) to localStorage, so
 * a half-filled integration survives a close/reopen, and a resume banner offers to pick one up.
 */

/** The `p.configFields` keys that hold a secret — the caller-supplied secret-key list the
 *  draft store blanks before persisting. */
function secretKeysOf(provider: ProviderCatalogEntry): string[] {
  return (provider.configFields ?? []).filter((f) => f.secret).map((f) => f.key);
}

/** Empty filter → every provider; otherwise a case-insensitive match on anything the row shows.
 *  The DESCRIPTION is searched too, now that the row displays it: a filter that cannot find what
 *  the operator is reading is a filter that looks broken. */
function matches(query: string, provider: ProviderCatalogEntry): boolean {
  const needle = query.trim().toLowerCase();
  if (!needle) return true;
  return (
    provider.displayName.toLowerCase().includes(needle) ||
    provider.subtitle.toLowerCase().includes(needle) ||
    (provider.description ?? "").toLowerCase().includes(needle)
  );
}

/** The DOM id of a row, so the filter box can point `aria-activedescendant` at it. */
const optionId = (providerId: string) => `add-int-option-${providerId}`;

export function AddIntegrationModal({
  open,
  onOpenChange,
  ecosystemId,
  providers,
  onAdded,
  initialFilter = "",
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  ecosystemId: string;
  /** The provider catalog from `integrationsApi.listProviders` (null while loading). */
  providers: ProviderCatalogEntry[] | null;
  onAdded: (row: MaskedProviderConfig) => void;
  /**
   * What the filter box starts on each time this opens — the host narrowing the picker to the
   * kind of service its screen is about. Shipr's Connections passes `"Code"`, so opening it
   * lands on the forges rather than on the whole alphabet with a git provider somewhere in it.
   *
   * A starting VALUE rather than a hidden restriction: it is in the box, visible, and the
   * operator can clear it. `providerIds` is the restriction, and it is a different prop.
   */
  initialFilter?: string;
}): ReactElement {
  const [filter, setFilter] = useState(initialFilter);
  /** The row Enter and OK would open. `null` means "whatever is first" — see `highlighted`. */
  const [highlightId, setHighlightId] = useState<string | null>(null);
  /** The provider whose own dialog is open over this one, if any. */
  const [configuringId, setConfiguringId] = useState<string | null>(null);
  const [draft, setDraft] = useState<IntegrationInput>(() => intBlank(""));
  // Provider ids with a persisted draft for THIS ecosystem — drives the resume banner.
  const [draftedIds, setDraftedIds] = useState<string[]>([]);
  const filterRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);

  // Reset to the pristine picker (and re-read this ecosystem's resumable drafts) on the
  // first render and whenever the modal transitions closed→open or the ecosystem changes
  // while open. base-ui keeps the Dialog mounted across open/close, so without this the
  // previous session's selection/filter would linger. This is React's "adjust state during
  // render when a prop changes" pattern (react.dev/reference/react/useState#storing-
  // information-from-previous-renders), which re-renders immediately without the cascading-
  // render cost of a setState-in-effect. The `null` sentinel makes the mount case (which
  // can already be open) run the same reset path as a later transition.
  const [session, setSession] = useState<{ open: boolean; ecosystemId: string } | null>(null);
  if (session === null || session.open !== open || session.ecosystemId !== ecosystemId) {
    setSession({ open, ecosystemId });
    setConfiguringId(null);
    setHighlightId(null);
    setFilter(initialFilter);
    setDraft(intBlank(""));
    setDraftedIds(open ? listDrafts(ecosystemId).map((d) => d.providerId) : []);
  }

  const visible = (providers ?? [])
    .slice()
    .sort((a, b) => a.displayName.localeCompare(b.displayName))
    .filter((p) => matches(filter, p));

  // DERIVED, not stored: the highlight falls back to the first visible row rather than being
  // corrected by an effect after each filter keystroke. A stored highlight would spend one
  // render pointing at a row the filter has just removed, which is exactly the render Enter
  // can land in.
  const highlighted = visible.find((p) => p.providerId === highlightId) ?? visible[0] ?? null;
  const configuring = configuringId
    ? (providers ?? []).find((p) => p.providerId === configuringId) ?? null
    : null;

  // Keep the highlighted row in view while arrowing. Queried from the DOM rather than kept in a
  // ref map: there is exactly one highlighted row and the list owns its own markup.
  useEffect(() => {
    const el = listRef.current?.querySelector('[data-highlighted="true"]');
    // Feature-detected, because jsdom has no layout and therefore no `scrollIntoView`. Detecting
    // it here rather than stubbing it in every suite that renders this list keeps the polyfill
    // out of tests that are not about scrolling.
    if (el && typeof el.scrollIntoView === "function") el.scrollIntoView({ block: "nearest" });
  }, [highlighted?.providerId]);

  const openProvider = (pid: string) => {
    setConfiguringId(pid);
    setDraft(loadDraft(ecosystemId, pid) ?? { ...intBlank(pid), name: "" });
  };

  const handleChange = (next: IntegrationInput) => {
    setDraft(next);
    if (configuring) {
      saveDraft(ecosystemId, configuring.providerId, next, secretKeysOf(configuring));
    }
  };

  const handleSaved = (row: MaskedProviderConfig) => {
    if (configuringId) {
      clearDraft(ecosystemId, configuringId);
      setDraftedIds((ids) => ids.filter((id) => id !== configuringId));
    }
    // Both dialogs close. The pane's `onAdded` selects the new instance, so what the operator
    // sees behind them is the integration they just added, open on its own detail — which is
    // the answer to "did that work?" that a stay-open modal with a cleared form never gave.
    setConfiguringId(null);
    onOpenChange(false);
    onAdded(row);
  };

  const discardDrafts = () => {
    for (const pid of draftedIds) clearDraft(ecosystemId, pid);
    setDraftedIds([]);
  };

  // Type to filter, arrows to move, Enter to choose — handled on the whole panel so it works
  // from the filter box (where focus starts and stays) and from the list alike. Escape is
  // deliberately NOT handled: it is the Dialog's, and cancelling the picker is what it should do.
  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (visible.length === 0) return;
    const at = highlighted ? visible.findIndex((p) => p.providerId === highlighted.providerId) : -1;
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setHighlightId(visible[Math.min(at + 1, visible.length - 1)]!.providerId);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setHighlightId(visible[Math.max(at - 1, 0)]!.providerId);
    } else if (e.key === "Home") {
      e.preventDefault();
      setHighlightId(visible[0]!.providerId);
    } else if (e.key === "End") {
      e.preventDefault();
      setHighlightId(visible[visible.length - 1]!.providerId);
    } else if (e.key === "Enter" && highlighted) {
      e.preventDefault();
      openProvider(highlighted.providerId);
    }
  };

  // The banner offers to resume an unfinished draft.
  const firstDraftedId = draftedIds[0];

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent
          initialFocus={filterRef}
          className="flex h-[32rem] max-h-[85vh] w-[calc(100%-2rem)] max-w-xl flex-col overflow-hidden"
        >
          <DialogHeader>
            <DialogTitle>Add integration</DialogTitle>
            <DialogDescription>Pick a service to configure for this ecosystem.</DialogDescription>
          </DialogHeader>

          <div className="flex min-h-0 flex-1 flex-col gap-3" onKeyDown={onKeyDown}>
            <label htmlFor="add-int-filter" className="sr-only">
              Filter services
            </label>
            <Input
              id="add-int-filter"
              ref={filterRef}
              value={filter}
              placeholder="Filter services"
              role="combobox"
              aria-expanded
              aria-controls="add-int-list"
              aria-activedescendant={highlighted ? optionId(highlighted.providerId) : undefined}
              onChange={(e) => setFilter(e.target.value)}
            />

            {firstDraftedId !== undefined && (
              <Alert variant="accent" className="flex items-center justify-between gap-2">
                <span className="text-sm text-apt-text">You have an unfinished integration.</span>
                <div className="flex gap-2">
                  <Button size="sm" variant="default" onClick={() => openProvider(firstDraftedId)}>
                    Resume
                  </Button>
                  <Button size="sm" variant="ghost" onClick={discardDrafts}>
                    Discard
                  </Button>
                </div>
              </Alert>
            )}

            {/* The one scroll region. Everything around it is fixed, so filtering moves nothing. */}
            <div
              ref={listRef}
              id="add-int-list"
              role="listbox"
              aria-label="Services"
              className="min-h-0 flex-1 overflow-y-auto rounded border border-apt-border"
            >
              {providers === null ? (
                <p className="px-3 py-2 text-sm text-apt-text-muted">Loading…</p>
              ) : visible.length === 0 ? (
                <p className="px-3 py-2 text-sm text-apt-text-muted">No services match.</p>
              ) : (
                visible.map((p) => {
                  const active = highlighted?.providerId === p.providerId;
                  return (
                    <div
                      key={p.providerId}
                      id={optionId(p.providerId)}
                      role="option"
                      aria-selected={active}
                      data-highlighted={active ? "true" : undefined}
                      onClick={() => setHighlightId(p.providerId)}
                      onDoubleClick={() => openProvider(p.providerId)}
                      className="cursor-pointer border-b border-apt-border/60 px-3 py-2 last:border-b-0 hover:bg-apt-surface-2 data-[highlighted]:bg-apt-gold/10"
                    >
                      <div className="flex items-baseline justify-between gap-3">
                        <span className="text-sm font-medium text-apt-text">{p.displayName}</span>
                        {p.subtitle && (
                          <span className="shrink-0 text-[11px] uppercase tracking-wide text-apt-text-dim">
                            {p.subtitle}
                          </span>
                        )}
                      </div>
                      {/* THE DESCRIPTION, which the catalog has always carried and this list has
                          never shown. A picker that names twelve services and describes none of
                          them makes the operator guess, and "GitHub" vs. "GitHub App" is exactly
                          the guess that goes wrong. Clamped to two lines so a long entry cannot
                          push the rows around. */}
                      {p.description && (
                        <p className="mt-0.5 line-clamp-2 text-xs text-apt-text-muted">
                          {p.description}
                        </p>
                      )}
                    </div>
                  );
                })
              )}
            </div>
          </div>

          <DialogFooter>
            <Button type="button" variant="ghost" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button
              type="button"
              disabled={!highlighted}
              onClick={() => highlighted && openProvider(highlighted.providerId)}
            >
              OK
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Mounted only while a provider is being configured, so its submit hook starts fresh per
          service rather than carrying the last one's error and busy flag. */}
      {configuring && (
        <ConfigureProviderDialog
          provider={configuring}
          ecosystemId={ecosystemId}
          draft={draft}
          onChange={handleChange}
          onSaved={handleSaved}
          onCancel={() => setConfiguringId(null)}
        />
      )}
    </>
  );
}

/**
 * ONE SERVICE, its fields, and OK/Cancel — the second half of adding an integration.
 *
 * Exported because it is a dialog about a provider and nothing about it is private to the
 * picker; the picker is simply the only thing that opens one today.
 *
 * The submit button is in the FOOTER, which is the whole reason `IntegrationDetailView` was
 * split into a hook and a body. A `<form>` wraps the scroll region and the footer together, so
 * the `type="submit"` OK is reached by Enter from any field for free — the platform's own
 * behaviour rather than a keydown handler that would have to re-decide which key means submit
 * inside a text field, a select and a textarea (`native-controls`). Escape is base-ui's, and
 * cancels.
 */
export function ConfigureProviderDialog({
  provider,
  ecosystemId,
  draft,
  onChange,
  onSaved,
  onCancel,
}: {
  provider: ProviderCatalogEntry;
  ecosystemId: string;
  draft: IntegrationInput;
  onChange: (next: IntegrationInput) => void;
  onSaved: (row: MaskedProviderConfig) => void;
  onCancel: () => void;
}): ReactElement {
  const submit = useIntegrationSubmit({
    provider,
    ecosystemId,
    mode: "add",
    config: null,
    draft,
    onChange,
    onSaved,
  });

  return (
    <Dialog open onOpenChange={(next) => !next && onCancel()}>
      <DialogContent className="flex max-h-[85vh] w-[calc(100%-2rem)] max-w-lg flex-col overflow-hidden">
        <DialogHeader>
          <DialogTitle>{provider.displayName}</DialogTitle>
          {/* The catalog's own copy, which is also what the picker row showed — so the dialog
              opens saying the same thing the operator just read, rather than restating it in a
              card halfway down the form. */}
          <DialogDescription>{provider.description || provider.subtitle}</DialogDescription>
        </DialogHeader>

        <form
          className="flex min-h-0 flex-1 flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            void submit.run();
          }}
        >
          <div className="min-h-0 flex-1 overflow-y-auto">
            <IntegrationDetailBody
              provider={provider}
              ecosystemId={ecosystemId}
              mode="add"
              config={null}
              draft={draft}
              onChange={onChange}
              submit={submit}
              hideSubmit
            />
          </div>
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={onCancel}>
              Cancel
            </Button>
            <Button type="submit" disabled={!submit.canSubmit || submit.busy}>
              {submit.busy ? submit.busyLabel : submit.label}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
