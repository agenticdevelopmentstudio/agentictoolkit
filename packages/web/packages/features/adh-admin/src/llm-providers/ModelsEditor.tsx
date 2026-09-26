"use client";

import { Plus, Trash2 } from "lucide-react";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { FieldGroup } from "@agenticdevelopertoolkit/ui/blocks/field-group";

/**
 * The model-name list editor: add/remove rows of plain strings. Mirrors the
 * origins editor in authentication/page.tsx (Input row + trailing Trash2 +
 * header "+ Add" button). The full list is always the desired set — the PUT
 * contract syncs `models` declaratively (matching names kept, missing
 * inserted, absent deleted), so there is no per-row dirty-tracking here.
 */
export function ModelsEditor({
  models,
  onChange,
  disabled,
}: {
  models: string[];
  onChange: (models: string[]) => void;
  disabled?: boolean;
}) {
  return (
    <FieldGroup
      title={`Models (${models.filter((m) => m.trim()).length})`}
      trailing={
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={disabled}
          onClick={() => onChange([...models, ""])}
        >
          <Plus className="size-4 mr-1" />
          Add
        </Button>
      }
    >
      {models.length === 0 && (
        <p className="text-xs text-apt-text-dim">No models yet.</p>
      )}
      {models.map((name, i) => (
        <div key={i} className="flex items-center gap-2">
          <Input
            aria-label={`Model ${i + 1} name`}
            value={name}
            onChange={(e) => {
              const next = [...models];
              next[i] = e.target.value;
              onChange(next);
            }}
            placeholder="e.g. gpt-4o"
            className="font-mono flex-1"
            disabled={disabled}
          />
          <Button
            type="button"
            variant="destructive-ghost"
            size="icon"
            disabled={disabled}
            onClick={() => onChange(models.filter((_, j) => j !== i))}
            aria-label={`Remove model ${name || i + 1}`}
            className="shrink-0"
          >
            <Trash2 className="size-4" />
          </Button>
        </div>
      ))}
    </FieldGroup>
  );
}
