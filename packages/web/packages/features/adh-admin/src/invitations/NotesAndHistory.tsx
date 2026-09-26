import type { ReactElement } from "react";
import { NotesAndHistory as SharedNotesAndHistory } from "@agentic-toolkit/adh-ui/blocks";
import { useRowNotes, useRowHistory } from "../api/invitations";

/**
 * Thin react-query wrapper around the shared presentational block. Fetches notes
 * and history for the subject and threads them into the shared component.
 */
export function NotesAndHistory({
  subjectTable,
  subjectId,
}: {
  subjectTable: string;
  subjectId: string;
}): ReactElement {
  const notes = useRowNotes(subjectTable, subjectId);
  const history = useRowHistory(subjectTable, subjectId);
  return (
    <SharedNotesAndHistory
      notes={notes.data ?? []}
      history={history.data ?? []}
      notesLoading={notes.isPending}
      historyLoading={history.isPending}
    />
  );
}
