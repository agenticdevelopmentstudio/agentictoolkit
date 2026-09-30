"use client";

import { useEffect, useMemo, useRef, useState, type FormEvent, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { Pencil } from "lucide-react";
import {
  useFeedback,
  useUpdateFeedback,
  type FeedbackSubmission,
} from "../api/admin";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { OptionMenu } from "@agenticdevelopertoolkit/ui/components/option-menu";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { DialogActions } from "@agenticdevelopertoolkit/ui/components/dialog-actions";
import { UnsavedChangesGuard } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-guard";
import { useAction } from "@agenticdevelopertoolkit/ui/hooks/useAction";
import { Field, ProgressModal } from "@agenticdevelopertoolkit/ui/blocks";
import { FeatureTitle } from "@agentic-toolkit/resource";
import {
  EditableList,
  useBatchRun,
  useEditableList,
  type EditableListColumn,
  type EditableListFacet,
} from "../components/editable-list";
import { formatDate, formatDateTime } from "../lib/timestamps";

/**
 * Feedback — every submission, and the two things an admin does to them: read one, and move a
 * batch along the triage statuses.
 *
 * The status control used to sit in each row, and it is the clearest case there is for why the
 * shared list puts actions in the BAR instead. Triage is a bulk verb: an admin works through a
 * morning's submissions and archives eleven of them, which was eleven separate menus. Status
 * means something across a selection, so it belongs to the selection — unlike the users page's
 * role menu, which stays in its row precisely because "make these nine admins" is not a thing
 * anyone means.
 *
 * The dialog is the other half of that trade. Moving status out of the row freed the space to
 * show what a submission actually SAYS: `body` and `adminNotes` are the two columns this page has
 * always fetched and never displayed, so triaging meant reading a subject line and guessing.
 */

const STATUSES = ["new", "reviewed", "resolved", "archived"] as const;
type Status = (typeof STATUSES)[number];

const titleCase = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

/** Where a submission is in triage, coloured by how much attention it still wants. */
const STATUS_VARIANT: Record<string, "orange" | "blue" | "success" | "neutral"> = {
  new: "orange",
  reviewed: "blue",
  resolved: "success",
  archived: "neutral",
};

const senderOf = (fb: FeedbackSubmission): string => fb.userEmail || "—";

export function FeedbackPane({ help }: { help?: ReactNode } = {}) {
  const { data, isLoading, error } = useFeedback();
  const updateFeedback = useUpdateFeedback();
  const router = useRouter();
  const rows = useMemo(() => data ?? [], [data]);

  // The dialog's TARGET and its OPENNESS are separate state, so closing does not wipe a
  // half-typed note. The draft resets only when the dialog is pointed at a DIFFERENT submission.
  const [editingId, setEditingId] = useState<string | null>(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [dialogDirty, setDialogDirty] = useState(false);

  const statusRun = useBatchRun({
    invalidateKey: ["admin", "feedback"],
    successMessage: "updated",
  });

  // Resolved from the LIVE rows, never captured at click time: a saved submission refetches, and a
  // dialog still comparing against the row as it looked before the save reads as permanently dirty
  // — which would leave the navigation guard armed forever.
  const editing = useMemo(
    () => rows.find((fb) => fb.id === editingId) ?? null,
    [rows, editingId],
  );

  const columns = useMemo<EditableListColumn<FeedbackSubmission>[]>(
    () => [
      { key: "category", header: "Category", width: "9rem", value: (fb) => fb.category },
      {
        key: "subject",
        header: "Subject",
        // minmax(0,1fr): take the leftover width, but shrink far enough to truncate.
        width: "minmax(0,1fr)",
        value: (fb) => fb.subject,
        render: (fb) => (
          <span className="block truncate text-sm text-apt-text" title={fb.subject}>
            {fb.subject || <span className="text-apt-text-dim">—</span>}
          </span>
        ),
      },
      {
        key: "email",
        header: "From",
        width: "16rem",
        value: senderOf,
        render: (fb) => (
          <span
            className="block truncate font-mono text-xs text-apt-text-muted"
            title={senderOf(fb)}
          >
            {senderOf(fb)}
          </span>
        ),
      },
      { key: "platform", header: "Platform", width: "8rem", value: (fb) => fb.platform },
      {
        key: "status",
        header: "Status",
        width: "8rem",
        value: (fb) => fb.status,
        render: (fb) => (
          <Badge variant={STATUS_VARIANT[fb.status] ?? "neutral"}>{fb.status}</Badge>
        ),
      },
      {
        key: "createdAt",
        header: "Received",
        width: "8rem",
        // Sorted by the RAW timestamp, shown formatted: sorting the formatted string would put
        // "Aug 3" before "Jul 9", and newest-first is the only order this page is read in.
        value: (fb) => fb.createdAt,
        render: (fb) => (
          <span
            className="whitespace-nowrap text-xs text-apt-text-dim"
            title={formatDateTime(fb.createdAt)}
          >
            {formatDate(fb.createdAt)}
          </span>
        ),
      },
    ],
    [],
  );

  const facets = useMemo<EditableListFacet<FeedbackSubmission>[]>(
    () => [
      {
        id: "status",
        label: "Status",
        valuesOf: (fb) => (fb.status ? [fb.status] : []),
        labelOf: titleCase,
      },
      { id: "category", label: "Category", valuesOf: (fb) => (fb.category ? [fb.category] : []) },
      { id: "platform", label: "Platform", valuesOf: (fb) => (fb.platform ? [fb.platform] : []) },
    ],
    [],
  );

  const list = useEditableList<FeedbackSubmission>({
    rows,
    getRowId: (fb) => fb.id,
    columns,
    facets,
    initialSort: { key: "createdAt", dir: "desc" },
  });

  const selected = list.selectedRows;

  /**
   * Move the selection to a status, skipping whatever is already there.
   *
   * A no-op PUT is a real write with a real `updatedAt`, and "updated eleven" when two moved is a
   * number the admin can't act on.
   */
  const applyStatus = (status: string) => {
    const changing = selected.filter((fb) => fb.status !== status);
    void statusRun.run(
      changing.map((fb) => ({ id: fb.id, label: fb.subject || senderOf(fb) })),
      (item) => updateFeedback.mutateAsync({ id: item.id, status }),
    );
  };

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <FeatureTitle
        title="Feedback"
        api={{ method: "GET", path: "/content/feedback", pathValues: {}, title: "Feedback API" }}
        help={help}
      />
      <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto px-6 pb-8 pt-2">
        {/* No New and no Delete: submissions arrive from the apps, and deleting one takes the only
            record of a report with it. Archiving is the disposal this page offers. */}
        <EditableList<FeedbackSubmission>
          list={list}
          ariaLabel="Feedback submissions"
          loading={isLoading}
          error={error}
          errorTitle="Couldn't load feedback"
          columnWidthsKey="admin-feedback"
          // Subject first, sender when a submission arrived without one — the same pair the batch
          // runner labels its rows with, so the progress modal and the checkboxes agree.
          describeRow={(fb) => fb.subject || senderOf(fb)}
          searchPlaceholder="Subject, sender or category"
          emptyLabel="No feedback."
          emptyFilteredLabel="No feedback matches these filters."
          actions={
            <>
              {/* One row, or nothing: the dialog reads ONE submission's body. */}
              <Button
                size="sm"
                variant="ghost"
                disabled={selected.length !== 1}
                onClick={() => {
                  setEditingId(selected[0]!.id);
                  setDialogOpen(true);
                }}
              >
                <Pencil data-icon="inline-start" />
                Open
              </Button>
              {/* A menu whose committed value is never kept: picking a status IS the action, so the
                  trigger goes on reading "Set status" instead of claiming the selection shares one. */}
              <OptionMenu
                ariaLabel="Set status for the selection"
                placeholder="Set status"
                items={STATUSES.map((s) => ({ value: s, label: titleCase(s) }))}
                value={null}
                disabled={selected.length === 0}
                onChange={(value) => applyStatus(value)}
                className="h-8 w-40"
              />
            </>
          }
        />

        <UnsavedChangesGuard when={dialogDirty} onNavigate={(href) => router.push(href)} />

        <FeedbackDialog
          // Keyed by the TARGET, not by openness: reopening the same submission restores the note
          // that was being typed, while pointing the dialog at another one remounts it.
          key={editingId ?? "none"}
          open={dialogOpen && editing !== null}
          feedback={editing}
          onClose={() => setDialogOpen(false)}
          onDirtyChange={setDialogDirty}
        />

        <ProgressModal
          open={statusRun.state.running || statusRun.state.finished}
          title="Updating feedback"
          description="Each submission is saved on its own; a failure leaves the earlier saves in place."
          total={statusRun.state.total}
          done={statusRun.state.done}
          currentLabel={statusRun.state.currentLabel}
          error={statusRun.state.error}
          results={statusRun.state.results}
          finished={statusRun.state.finished}
          onContinue={statusRun.continueRun}
          onStop={statusRun.stop}
          onClose={() => {
            statusRun.reset();
            list.clearSelection();
          }}
        />
      </div>
    </div>
  );
}

/**
 * One submission: what it says, and the two fields an admin owns.
 *
 * `body` is read-only because it is the user's words — the whole value of the record is that it
 * still says what they said. `adminNotes` is where this side's account goes, which is why the two
 * are shown together rather than the note living in a column nobody reads.
 */
export function FeedbackDialog({
  open,
  feedback,
  onClose,
  onDirtyChange,
}: {
  open: boolean;
  /** The row being read, or `null` when the dialog is closed. There is no create mode. */
  feedback: FeedbackSubmission | null;
  onClose: () => void;
  /** Reports whether the note holds unsaved input, so the page's guard covers it. */
  onDirtyChange: (dirty: boolean) => void;
}) {
  const updateFeedback = useUpdateFeedback();
  const save = useAction();

  const initialStatus = feedback?.status ?? "";
  const initialNotes = feedback?.adminNotes ?? "";
  const [status, setStatus] = useState(initialStatus);
  const [notes, setNotes] = useState(initialNotes);
  const formRef = useRef<HTMLFormElement>(null);

  const dirty = status !== initialStatus || notes !== initialNotes;
  // Reported whether or not the dialog is OPEN. Closing keeps the draft (the page keys this
  // component by the target, not by openness), so a shut dialog holding an unsaved note is exactly
  // the case the navigation guard exists for.
  useEffect(() => onDirtyChange(dirty), [dirty, onDirtyChange]);

  function close() {
    if (save.busy) return;
    onClose();
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!feedback) return;
    void save.run(async () => {
      // Only what changed. The endpoint is a patch, so sending both would write back the field the
      // admin never touched, undoing whatever landed on it while the dialog sat open.
      await updateFeedback.mutateAsync({
        id: feedback.id,
        status: status === initialStatus ? undefined : status,
        adminNotes: notes === initialNotes ? undefined : notes,
      });
      onClose();
    });
  }

  const meta = feedback
    ? [feedback.platform, feedback.appVersion, feedback.osVersion, feedback.deviceInfo]
        .filter(Boolean)
        .join(" · ")
    : "";

  return (
    <Dialog open={open} onOpenChange={(next) => !next && close()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{feedback?.subject || "Feedback"}</DialogTitle>
          <DialogDescription>
            {feedback
              ? `${feedback.category || "Uncategorised"} · ${senderOf(feedback)} · ${formatDateTime(feedback.createdAt)}`
              : ""}
          </DialogDescription>
        </DialogHeader>
        <form ref={formRef} onSubmit={handleSubmit} className="flex flex-col gap-4">
          <Field label="What they wrote">
            {/* The submitter's own words, shown whole and never edited from here. */}
            <p className="max-h-60 overflow-y-auto whitespace-pre-wrap rounded-md border border-apt-border bg-apt-surface p-3 text-sm text-apt-text">
              {feedback?.body || <span className="text-apt-text-dim">No message.</span>}
            </p>
          </Field>
          {meta && <p className="text-xs text-apt-text-dim">{meta}</p>}
          <Field label="Status">
            <Select aria-label="Status" value={status} onChange={(e) => setStatus(e.target.value)}>
              {/* An unknown stored value keeps an option of its own: a row whose status came from
                  somewhere else must not be silently rewritten by opening it. */}
              {status !== "" && !STATUSES.includes(status as Status) && (
                <option value={status}>{status}</option>
              )}
              {STATUSES.map((s) => (
                <option key={s} value={s}>
                  {titleCase(s)}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Admin notes" error={save.error}>
            <Textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="What was done about this"
              rows={4}
            />
          </Field>
          {/* A submit button is what lets Enter submit the form; hidden because the visible confirm
              lives in DialogActions and calls form.requestSubmit(). It carries the same disabled
              state as that confirm — being the form's default button, Enter submits THIS one
              regardless of `hidden`, and only `disabled` stops it. */}
          <button
            type="submit"
            className="hidden"
            aria-hidden
            tabIndex={-1}
            disabled={!dirty || save.busy}
          />
        </form>
        <DialogActions
          cancelLabel="Cancel"
          onCancel={close}
          confirmLabel="Save"
          onConfirm={() => formRef.current?.requestSubmit()}
          busy={save.busy}
          confirmDisabled={!dirty}
          focusOnMount={false}
        />
      </DialogContent>
    </Dialog>
  );
}
