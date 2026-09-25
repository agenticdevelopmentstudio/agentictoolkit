"use client";

import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { RdidEditor } from "@agentic-toolkit/adh-ui/components/rdid-editor";
import { isRdid } from "@agentic-toolkit/adh-ui/rdid";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  APPLICATION_KINDS,
  type ApplicationInput,
  type ApplicationKind,
  type PrototypeApplication,
} from "../api/applications-prototype";
import { DetailSection, unchangedFromStored } from "@agentic-toolkit/resource";
import { SchemaPermissionsSection } from "./SchemaPermissionsSection";
import { AccessTokensSection } from "./AccessTokensSection";
import type { RenderTransferSection } from "../transfer-seam";

export function appBlank(): ApplicationInput {
  return { identifier: "", name: "", kind: "developer", schemaGrants: [] };
}

/**
 * Split an application id into its fixed inherited prefix (`app.<ecosystem>.`) and the
 * editable leaf. A SAVED app derives the prefix from its own id; a NEW one uses the
 * ecosystem `scopePrefix`. When no prefix can be derived (e.g. the all-ecosystems view),
 * the whole id is treated as the leaf (a free identifier field, validated as type-prefixed).
 */
function splitIdentifier(
  identifier: string,
  saved: boolean,
  scopePrefix: string,
): { prefix: string; leaf: string } {
  if (saved) {
    const i = identifier.lastIndexOf(".");
    return i >= 0
      ? { prefix: identifier.slice(0, i + 1), leaf: identifier.slice(i + 1) }
      : { prefix: "", leaf: identifier };
  }
  if (scopePrefix) {
    return {
      prefix: scopePrefix,
      leaf: identifier.startsWith(scopePrefix) ? identifier.slice(scopePrefix.length) : "",
    };
  }
  return { prefix: "", leaf: identifier };
}

export function appToInput(a: PrototypeApplication): ApplicationInput {
  return {
    identifier: a.identifier,
    name: a.name,
    kind: a.kind,
    schemaGrants: a.schemaGrants,
  };
}

/** Returns an error message, or null when the draft is valid. `storedIdentifier` is the id already
 *  on the record being edited (absent on a create). It exempts the id from the type-prefix/rdid
 *  FORMAT rule only — same reasoning as `teamValidate`'s stored-identifier exemption
 *  (`@agentic-toolkit/teams`): a row the backend wrote need not satisfy a client-side format rule
 *  added later, and holding every other field's Save hostage to it is the bug this grandfathers.
 *  Required-ness and uniqueness are never exempt: an empty or duplicate id is still refused even
 *  when untouched (Mike, 2026-09-25). */
export function appValidate(
  draft: ApplicationInput,
  takenIdentifiers: string[] = [],
  storedIdentifier?: string,
): string | null {
  const id = draft.identifier.trim();
  if (!id) return "Id is required.";
  // isRdid validates EVERY segment (type prefix + each dotted segment), not just the leaf, so a
  // malformed interior scope (e.g. an all-ecosystems free-text entry) is caught client-side too.
  // Skipped for an id unchanged from what's stored — see the doc above.
  if (
    !unchangedFromStored(id, storedIdentifier) &&
    (!id.startsWith("app.") || !isRdid(id))
  )
    return "Id must be a type-prefixed application id, e.g. app.my-ecosystem.my-app";
  if (takenIdentifiers.includes(id)) return `Id "${id}" is already in use.`;
  if (!draft.name.trim()) return "Name is required.";
  return null;
}

/**
 * The application's PLACEMENT fields — name, id, and consumer kind — shared by the full
 * detail and the "New application" create modal (HTD recipe `must-create-in-modal`), so the
 * `app.<ecosystem>.` id-splitting lives in one place. Everything else (schema grants, access
 * tokens) belongs to the detail that opens once the created app is selected.
 */
export function ApplicationPlacementFields({
  draft,
  onChange,
  app,
  scopePrefix,
  autoFocusName,
}: {
  draft: ApplicationInput;
  onChange: (next: ApplicationInput) => void;
  /** The saved application, when editing an existing one (null while creating). */
  app: PrototypeApplication | null;
  /** Fixed `app.<ecosystem>.` prefix for a NEW id (empty ⇒ free identifier field). */
  scopePrefix: string;
  /** Focus the Name field on mount (the create modal opens straight into it). */
  autoFocusName?: boolean;
}) {
  const idParts = splitIdentifier(draft.identifier, app !== null, scopePrefix);
  return (
    <>
      <div className="flex flex-col gap-2">
        <Label htmlFor="app-name">Name</Label>
        <Input
          id="app-name"
          /* eslint-disable-next-line jsx-a11y/no-autofocus -- focus the first field when the modal opens */
          autoFocus={autoFocusName}
          value={draft.name}
          placeholder="My Application"
          onChange={(e) => onChange({ ...draft, name: e.target.value })}
        />
      </div>
      <RdidEditor
        id="app-id"
        label="Id"
        prefix={idParts.prefix}
        value={idParts.prefix ? idParts.leaf : draft.identifier}
        placeholder={idParts.prefix ? "my-app" : "app.my-ecosystem.my-app"}
        hint="Only the final name is editable — the app. type and the ecosystem scope are inherited."
        onChange={(next) =>
          onChange({
            ...draft,
            identifier: idParts.prefix ? idParts.prefix + next : next,
          })
        }
      />
      <div className="flex flex-col gap-2">
        <Label htmlFor="app-kind">Consumer kind</Label>
        <Select
          id="app-kind"
          value={draft.kind}
          onChange={(e) => onChange({ ...draft, kind: e.target.value as ApplicationKind })}
        >
          {APPLICATION_KINDS.map((k) => (
            <option key={k} value={k}>
              {k}
            </option>
          ))}
        </Select>
        <p className="text-xs text-apt-text-muted">Who consumes this application.</p>
      </div>
    </>
  );
}

/**
 * Controlled application form — fields + schema grants only. Save/Cancel/Delete
 * live in the MasterDetailLayout button bar; the pane owns the draft +
 * dirty/validity state. Access tokens are a SEPARATE sub-section that persists
 * independently of the unsaved field edits, so they keep their own actions and
 * are NOT part of the save draft.
 */
export function ApplicationDetail({
  title,
  draft,
  onChange,
  error,
  app,
  scopePrefix,
  ecosystemRdid,
  renderTransfer,
}: {
  title: string;
  draft: ApplicationInput;
  onChange: (next: ApplicationInput) => void;
  error?: string | null;
  /** The saved application, when editing an existing one (null while creating). */
  app: PrototypeApplication | null;
  /** Fixed `app.<ecosystem>.` prefix for a NEW id (empty ⇒ free identifier field). */
  scopePrefix: string;
  /**
   * The owning Product's scope, as `ApplicationsPane` itself received it (its `ecosystemId`
   * prop) — passed straight through to the host's transfer renderer, which is the one place that
   * decides whether it's usable as a transfer `currentTarget` (see {@link RenderTransferSection}).
   * Not named
   * `ecosystemId` here: `app.ecosystemId` already means something else on this file's own row
   * type (a raw uuid) — this is the PANE's scope, not the entity's own foreign key.
   */
  ecosystemRdid?: string;
  /** The host's Transfer Ownership section; omitted ⇒ the application offers no transfer. */
  renderTransfer?: RenderTransferSection;
}) {
  return (
    <>
      <DetailSection title={title}>
        <Card>
          <CardContent className="flex flex-col gap-5">
            <ApplicationPlacementFields
              draft={draft}
              onChange={onChange}
              app={app}
              scopePrefix={scopePrefix}
            />

            <ErrorText error={error} />
          </CardContent>
        </Card>
      </DetailSection>

      <SchemaPermissionsSection
        grants={draft.schemaGrants}
        onChange={(schemaGrants) => onChange({ ...draft, schemaGrants })}
        ecosystemRdid={ecosystemRdid}
      />

      {app ? (
        <AccessTokensSection appId={app.id} />
      ) : (
        <EmptyState className="min-h-0 px-3 py-4" title="Save the application to create access tokens." />
      )}

      {/* Only once the application is SAVED — there is nothing to transfer while still drafting
          one. `ecosystemRdid` here is the PANE's scope (see the prop doc above), not derived
          from `app` itself — `PrototypeApplication` only carries `ecosystemId` as a raw uuid. */}
      {app &&
        renderTransfer?.({
          entityNoun: "Application",
          entityType: "application",
          entityId: app.id,
          entityLabel: app.identifier,
          ecosystemRdid,
        })}
    </>
  );
}
