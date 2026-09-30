"use client";

import { useState } from "react";
import type { ReactNode } from "react";

import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Plus, Trash2 } from "lucide-react";

/**
 * A column of URL text inputs a developer adds to and removes from — the shape shared by the
 * sign-in app's allowed return origins and its redirect URIs. The values live in the parent as a
 * plain `string[]`, but a column of text inputs needs a STABLE key per row so removing a middle
 * row doesn't churn the focus/caret of the rows below (array-index keys would). So this editor
 * holds an id-annotated mirror as its own source of truth and projects back to `string[]` on
 * every edit. It is remounted (via a `key` the caller puts on it, keyed to the persisted values)
 * whenever the server re-hydrates a different canonical set — the React-blessed way to reset
 * derived state — so nothing is synced from props during render.
 */
type Row = { id: number; value: string };

export function UrlRowsEditor({
  label,
  helpText,
  placeholder,
  addLabel,
  removeLabel,
  values,
  onChange,
}: {
  label: string;
  helpText: ReactNode;
  placeholder: string;
  /** The "Add …" button's label. */
  addLabel: string;
  /** Each row's remove button title (and accessible name). */
  removeLabel: string;
  /** Current values; also the initial row values (read only at mount — see the caller's `key`). */
  values: string[];
  onChange: (next: string[]) => void;
}) {
  const [rows, setRows] = useState<Row[]>(() => values.map((value, i) => ({ id: i, value })));
  const emit = (next: Row[]) => {
    setRows(next);
    onChange(next.map((r) => r.value));
  };
  const setValue = (id: number, value: string) =>
    emit(rows.map((r) => (r.id === id ? { ...r, value } : r)));
  // New ids are max(existing)+1 so they never collide with a surviving row.
  const addRow = () => emit([...rows, { id: rows.reduce((m, r) => Math.max(m, r.id), -1) + 1, value: "" }]);
  const removeRow = (id: number) => emit(rows.filter((r) => r.id !== id));

  return (
    <div className="flex flex-col gap-2">
      <Label>{label}</Label>
      <p className="text-xs text-apt-text-muted">{helpText}</p>
      <div className="flex flex-col gap-2">
        {rows.map((row) => (
          <div key={row.id} className="flex items-center gap-2">
            <Input
              value={row.value}
              placeholder={placeholder}
              onChange={(e) => setValue(row.id, e.target.value)}
            />
            <Button
              type="button"
              variant="destructive-ghost"
              size="icon-sm"
              onClick={() => removeRow(row.id)}
              title={removeLabel}
            >
              <Trash2 />
            </Button>
          </div>
        ))}
        <Button type="button" variant="outline" size="sm" onClick={addRow}>
          <Plus data-icon="inline-start" />
          {addLabel}
        </Button>
      </div>
    </div>
  );
}
