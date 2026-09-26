"use client";

import { Plus, Trash2 } from "lucide-react";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Checkbox } from "@agenticdevelopertoolkit/ui/components/checkbox";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { FieldGroup } from "@agenticdevelopertoolkit/ui/blocks/field-group";
import {
  newLocalId,
  type ConnectionSpecDraft,
  type HeaderVarRow,
  type KVRow,
  type UrlVarRow,
} from "./connection-spec-draft";

/**
 * The connectionSpec sub-editor: auth type + type-specific fields, url
 * variables (base_url `{placeholders}` the connect UI prompts for), default
 * query params, and extra headers. A controlled draft — the parent
 * (ProviderTemplateDialog) owns the state and assembles the final
 * ConnectionSpec via `connectionSpecFromDraft` on save.
 */
export function ConnectionSpecFields({
  draft,
  onChange,
  disabled,
}: {
  draft: ConnectionSpecDraft;
  onChange: (patch: Partial<ConnectionSpecDraft>) => void;
  disabled?: boolean;
}) {
  return (
    <div className="flex flex-col gap-4">
      <FieldGroup title="Authentication">
        <Field label="Auth type">
          <Select
            aria-label="Auth type"
            value={draft.authType}
            onChange={(e) =>
              onChange({ authType: e.target.value as ConnectionSpecDraft["authType"] })
            }
            disabled={disabled}
          >
            <option value="none">None / Bearer (default)</option>
            <option value="header">Custom header</option>
            <option value="sigv4">AWS SigV4</option>
            <option value="oauth2">OAuth2</option>
          </Select>
        </Field>

        {draft.authType === "header" && (
          <div className="flex flex-col gap-3 sm:flex-row">
            <Field label="Header name" className="flex-1">
              <Input
                value={draft.header}
                onChange={(e) => onChange({ header: e.target.value })}
                placeholder="api-key"
                className="font-mono"
                disabled={disabled}
              />
            </Field>
            <Field label="Scheme" className="w-40">
              <Select
                aria-label="Header scheme"
                value={draft.scheme}
                onChange={(e) =>
                  onChange({ scheme: e.target.value as ConnectionSpecDraft["scheme"] })
                }
                disabled={disabled}
              >
                <option value="bearer">Bearer</option>
                <option value="raw">Raw</option>
              </Select>
            </Field>
          </div>
        )}

        {draft.authType === "sigv4" && (
          <Field label="Region" hint="Reserved — not yet enforced by the backend client.">
            <Input
              value={draft.region}
              onChange={(e) => onChange({ region: e.target.value })}
              placeholder="us-east-1"
              className="font-mono"
              disabled={disabled}
            />
          </Field>
        )}

        {draft.authType === "oauth2" && (
          <Field label="Token URL" hint="Reserved — not yet enforced by the backend client.">
            <Input
              value={draft.tokenUrl}
              onChange={(e) => onChange({ tokenUrl: e.target.value })}
              placeholder="https://example.com/oauth/token"
              className="font-mono"
              disabled={disabled}
            />
          </Field>
        )}
      </FieldGroup>

      <FieldGroup
        title="URL variables"
        trailing={
          <Button
            type="button"
            variant="outline"
            size="sm"
            disabled={disabled}
            onClick={() =>
              onChange({
                urlVars: [
                  ...draft.urlVars,
                  { localId: newLocalId("uv"), name: "", label: "", example: "", secret: false },
                ],
              })
            }
          >
            <Plus className="size-4 mr-1" />
            Add
          </Button>
        }
      >
        {draft.urlVars.length === 0 && (
          <p className="text-xs text-apt-text-dim">
            None — base_url has no {"{placeholders}"} to prompt for.
          </p>
        )}
        {draft.urlVars.map((row, i) => (
          <UrlVarRowEditor
            key={row.localId}
            row={row}
            disabled={disabled}
            onChange={(patch) => {
              const next = [...draft.urlVars];
              next[i] = { ...row, ...patch };
              onChange({ urlVars: next });
            }}
            onRemove={() => onChange({ urlVars: draft.urlVars.filter((_, j) => j !== i) })}
          />
        ))}
      </FieldGroup>

      <FieldGroup
        title="Header variables"
        trailing={
          <Button
            type="button"
            variant="outline"
            size="sm"
            disabled={disabled}
            onClick={() =>
              onChange({
                headerVars: [
                  ...draft.headerVars,
                  { localId: newLocalId("hv"), header: "", label: "", example: "", secret: false },
                ],
              })
            }
          >
            <Plus className="size-4 mr-1" />
            Add
          </Button>
        }
      >
        {draft.headerVars.length === 0 && (
          <p className="text-xs text-apt-text-dim">
            None — no header value the connect UI should prompt for per connection.
          </p>
        )}
        {draft.headerVars.map((row, i) => (
          <HeaderVarRowEditor
            key={row.localId}
            row={row}
            disabled={disabled}
            onChange={(patch) => {
              const next = [...draft.headerVars];
              next[i] = { ...row, ...patch };
              onChange({ headerVars: next });
            }}
            onRemove={() => onChange({ headerVars: draft.headerVars.filter((_, j) => j !== i) })}
          />
        ))}
      </FieldGroup>

      <KVListFieldGroup
        title="Default query params"
        rows={draft.defaultQuery}
        onRowsChange={(rows) => onChange({ defaultQuery: rows })}
        disabled={disabled}
        keyPlaceholder="api-version"
        valuePlaceholder="2024-10-01"
      />

      <KVListFieldGroup
        title="Extra headers"
        rows={draft.extraHeaders}
        onRowsChange={(rows) => onChange({ extraHeaders: rows })}
        disabled={disabled}
        keyPlaceholder="anthropic-version"
        valuePlaceholder="2023-06-01"
      />
    </div>
  );
}

function UrlVarRowEditor({
  row,
  onChange,
  onRemove,
  disabled,
}: {
  row: UrlVarRow;
  onChange: (patch: Partial<UrlVarRow>) => void;
  onRemove: () => void;
  disabled?: boolean;
}) {
  return (
    <div className="flex flex-col gap-2 rounded-md border border-apt-border p-2">
      <div className="flex items-center gap-2">
        <Input
          aria-label="Variable name"
          value={row.name}
          onChange={(e) => onChange({ name: e.target.value })}
          placeholder="name (e.g. region)"
          className="font-mono flex-1"
          disabled={disabled}
        />
        <Button
          type="button"
          variant="destructive-ghost"
          size="icon"
          disabled={disabled}
          onClick={onRemove}
          aria-label="Remove URL variable"
          className="shrink-0"
        >
          <Trash2 className="size-4" />
        </Button>
      </div>
      <div className="flex items-center gap-2">
        <Input
          aria-label="Label"
          value={row.label}
          onChange={(e) => onChange({ label: e.target.value })}
          placeholder="label (e.g. Region)"
          className="flex-1"
          disabled={disabled}
        />
        <Input
          aria-label="Example value"
          value={row.example}
          onChange={(e) => onChange({ example: e.target.value })}
          placeholder="example (e.g. us-east-1)"
          className="flex-1"
          disabled={disabled}
        />
      </div>
      <Label className="font-normal">
        <Checkbox
          checked={row.secret}
          onCheckedChange={(v) => onChange({ secret: v === true })}
          disabled={disabled}
        />
        Secret (masked in the connect UI)
      </Label>
    </div>
  );
}

function HeaderVarRowEditor({
  row,
  onChange,
  onRemove,
  disabled,
}: {
  row: HeaderVarRow;
  onChange: (patch: Partial<HeaderVarRow>) => void;
  onRemove: () => void;
  disabled?: boolean;
}) {
  return (
    <div className="flex flex-col gap-2 rounded-md border border-apt-border p-2">
      <div className="flex items-center gap-2">
        <Input
          aria-label="Header name"
          value={row.header}
          onChange={(e) => onChange({ header: e.target.value })}
          placeholder="header (e.g. x-portkey-provider)"
          className="font-mono flex-1"
          disabled={disabled}
        />
        <Button
          type="button"
          variant="destructive-ghost"
          size="icon"
          disabled={disabled}
          onClick={onRemove}
          aria-label="Remove header variable"
          className="shrink-0"
        >
          <Trash2 className="size-4" />
        </Button>
      </div>
      <div className="flex items-center gap-2">
        <Input
          aria-label="Label"
          value={row.label}
          onChange={(e) => onChange({ label: e.target.value })}
          placeholder="label (e.g. Upstream provider)"
          className="flex-1"
          disabled={disabled}
        />
        <Input
          aria-label="Example value"
          value={row.example}
          onChange={(e) => onChange({ example: e.target.value })}
          placeholder="example (e.g. openai)"
          className="flex-1"
          disabled={disabled}
        />
      </div>
      <Label className="font-normal">
        <Checkbox
          checked={row.secret}
          onCheckedChange={(v) => onChange({ secret: v === true })}
          disabled={disabled}
        />
        Secret (masked in the connect UI)
      </Label>
    </div>
  );
}

function KVListFieldGroup({
  title,
  rows,
  onRowsChange,
  disabled,
  keyPlaceholder,
  valuePlaceholder,
}: {
  title: string;
  rows: KVRow[];
  onRowsChange: (rows: KVRow[]) => void;
  disabled?: boolean;
  keyPlaceholder?: string;
  valuePlaceholder?: string;
}) {
  return (
    <FieldGroup
      title={title}
      trailing={
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={disabled}
          onClick={() =>
            onRowsChange([...rows, { localId: newLocalId("kv"), key: "", value: "" }])
          }
        >
          <Plus className="size-4 mr-1" />
          Add
        </Button>
      }
    >
      {rows.length === 0 && <p className="text-xs text-apt-text-dim">None.</p>}
      {rows.map((row, i) => (
        <div key={row.localId} className="flex items-center gap-2">
          <Input
            aria-label="Key"
            value={row.key}
            onChange={(e) => {
              const next = [...rows];
              next[i] = { ...row, key: e.target.value };
              onRowsChange(next);
            }}
            placeholder={keyPlaceholder}
            className="font-mono flex-1"
            disabled={disabled}
          />
          <Input
            aria-label="Value"
            value={row.value}
            onChange={(e) => {
              const next = [...rows];
              next[i] = { ...row, value: e.target.value };
              onRowsChange(next);
            }}
            placeholder={valuePlaceholder}
            className="font-mono flex-1"
            disabled={disabled}
          />
          <Button
            type="button"
            variant="destructive-ghost"
            size="icon"
            disabled={disabled}
            onClick={() => onRowsChange(rows.filter((_, j) => j !== i))}
            aria-label={`Remove ${title.toLowerCase()} row`}
            className="shrink-0"
          >
            <Trash2 className="size-4" />
          </Button>
        </div>
      ))}
    </FieldGroup>
  );
}
