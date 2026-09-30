"use client";

import { useEffect, useRef, type ReactNode } from "react";
import { TopicSelectHint } from "@agenticdevelopertoolkit/ui/blocks";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { ButtonBar } from "./master-detail/MasterDetailLayout";
import type { RecordAffordanceProps } from "./record-affordance";
import type { MasterDetailForm } from "./master-detail/useMasterDetailForm";

/**
 * The shared single-record Settings pane (the active ecosystem/service/team). It
 * binds the form to the active record — via a ref guard so a list refresh (e.g.
 * the service Connect action) doesn't re-select and clobber unsaved edits — then
 * renders the gold feature title, the master/detail button bar (no "New …", since
 * creation happens through the sidebar popup dialog), and the entity detail (or an
 * empty state). `extraActions` slots a per-entity control above the form.
 */
export function RecordSettingsPane<TItem, TInput>({
  form,
  activeId,
  items,
  getId,
  title,
  help,
  trailing,
  api,
  loadError,
  emptyLabel,
  extraActions,
  renderDetail,
}: {
  form: MasterDetailForm<TItem, TInput>;
  activeId?: string;
  items: TItem[] | null;
  getId: (item: TItem) => string;
  title?: ReactNode;
  help?: ReactNode;
  /** Optional non-API affordance on the button bar, left of the API button. */
  trailing?: ReactNode;
  /** The active record's endpoint, for the bar's API button (see {@link ButtonBar}'s `api`). */
  api?: RecordAffordanceProps | null;
  loadError?: string | null;
  emptyLabel: string;
  /** Optional control rendered above the form (e.g. a Connect button). */
  extraActions?: ReactNode;
  /** The entity detail form; called with the non-null draft only while editing. */
  renderDetail: (draft: TInput) => ReactNode;
}) {
  const { select } = form;
  const boundIdRef = useRef<string | undefined>(undefined);
  useEffect(() => {
    if (
      activeId &&
      activeId !== boundIdRef.current &&
      items?.some((i) => getId(i) === activeId)
    ) {
      boundIdRef.current = activeId;
      select(activeId);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeId, items]);

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      {/* The centered title + help live in the bar itself; New lives in the resource view's
          rail and Delete in the entity pane's Danger section, so this bar keeps just Cancel/Save. */}
      <ButtonBar actions={form.actions} showCreate={false} showDelete={false} title={title} trailing={trailing} api={api} help={help} />
      <section className="flex min-h-0 min-w-0 flex-1 flex-col gap-6 overflow-y-auto px-6 py-4">
        <ErrorText error={loadError} />
        {form.editing && form.draft ? (
          <>
            {extraActions}
            {renderDetail(form.draft)}
          </>
        ) : (
          // The shared select-hint card, so this pane's placeholder matches the stack
          // frontier's nudge and every other "pick something" pane.
          <TopicSelectHint title={emptyLabel} />
        )}
      </section>
    </div>
  );
}
