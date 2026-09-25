"use client";

import { Field } from "@agenticdevelopertoolkit/ui/blocks";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { RdidEditor } from "@agentic-toolkit/adh-ui/components/rdid-editor";
import { rdidPrefix, validateLeaf } from "@agentic-toolkit/adh-ui/rdid";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { slugifyBucketName } from "./schema-model";
import type { SchemaDefinition, SchemaDefinitionInput, SchemaTable } from "./schema-model";
import { DetailSection, unchangedFromStored } from "@agentic-toolkit/resource";
import { DeleteEntitySection } from "@agentic-toolkit/adh-ui/blocks";
import type { RenderTransferSection } from "../transfer-seam";

export function schemaBlank(): SchemaDefinitionInput {
  return { name: "", slug: "", description: "", tables: [] };
}

export function schemaToInput(s: SchemaDefinition): SchemaDefinitionInput {
  return { name: s.name, slug: s.slug, description: s.description, tables: s.tables };
}

/**
 * The `storage.<eco path>.` a bucket's slug sits under — from its own rdid once saved, else from the
 * pane's ecosystem (`ecosystem.<path>` → `storage.<path>.`). Empty when neither is an rdid, and the
 * editor then shows a bare slug box.
 */
export function bucketSlugPrefix(bucketId: string | undefined, ecosystemRdid: string | undefined): string {
  if (bucketId) return rdidPrefix(bucketId);
  return ecosystemRdid?.startsWith("ecosystem.")
    ? `storage.${ecosystemRdid.slice("ecosystem.".length)}.`
    : "";
}

/**
 * Name and slug together: the slug follows the name until the user edits it themselves, the same
 * pre-fill the Add-table dialog does for a table's name from its type. A slug that still equals
 * the previous name's derivation has not been edited.
 */
export function withName(draft: SchemaDefinitionInput, name: string): SchemaDefinitionInput {
  const following = !draft.slug || draft.slug === slugifyBucketName(draft.name);
  return { ...draft, name, slug: following ? slugifyBucketName(name) : draft.slug };
}

/**
 * The Slug box — the bucket's rdid leaf behind its fixed `storage.<eco path>.` prefix
 * ("buckets need unique slugs and rdids" (Mike, 2026-09-24)). Shared by the create modal and
 * Settings so the two cannot disagree on what a slug is.
 */
export function BucketSlugField({
  draft,
  onChange,
  prefix,
}: {
  draft: SchemaDefinitionInput;
  onChange: (next: SchemaDefinitionInput) => void;
  prefix: string;
}) {
  return (
    <RdidEditor
      label="Slug"
      prefix={prefix}
      value={draft.slug}
      placeholder="profile-basics"
      hint="Unique among this ecosystem's buckets. Changing it changes the bucket's id."
      error={draft.slug ? validateLeaf(draft.slug) : null}
      onChange={(slug) => onChange({ ...draft, slug })}
    />
  );
}

/** Returns an error message for a new table's name, or null when it is valid. Names are unique
 *  per bucket (backend unique (bucket, name) index), so a clash is caught here rather than
 *  thrown mid-save. */
export function tableNameValidate(name: string, tables: SchemaTable[]): string | null {
  const n = name.trim();
  if (!n) return "Name is required.";
  if (tables.some((t) => t.name.trim().toLowerCase() === n.toLowerCase()))
    return `A table named "${n}" already exists in this bucket.`;
  return null;
}

/** Returns an error message, or null when the draft is valid. `others` are the ecosystem's other
 *  buckets, whose names and slugs this one may not reuse. The draft's `tables` are not checked:
 *  neither form validated with this edits them (the create modal starts them empty; Settings
 *  neither shows nor saves them), so a check here could only block a save over a stored list the
 *  user cannot see. A table's name is {@link tableNameValidate}'s, as the table is added or
 *  edited.
 *
 *  `storedSlug` is the slug already on the bucket being edited (absent on a create). It exempts
 *  the slug's FORMAT/length rules only — same reasoning as `teamValidate`'s stored-identifier
 *  exemption: a bucket the backend already accepted need not satisfy a client-side rule added
 *  later, and refusing it holds the Name/Description fields' Save hostage to a slug nobody is
 *  touching. Uniqueness against `others` and the Name-required rule are never exempt (Mike,
 *  2026-09-25). */
export function schemaValidate(
  draft: SchemaDefinitionInput,
  others: Pick<SchemaDefinition, "name" | "slug">[] = [],
  storedSlug?: string,
): string | null {
  const name = draft.name.trim();
  if (!name) return "Name is required.";
  if (others.some((o) => o.name.toLowerCase() === name.toLowerCase()))
    return `A bucket named "${name}" already exists.`;
  const slug = draft.slug.trim();
  if (!unchangedFromStored(slug, storedSlug)) {
    const slugProblem = validateLeaf(slug);
    if (slugProblem) return `Slug: ${slugProblem}`;
    if (slug.length > 64) return "Slug: 64 characters at most.";
  }
  if (others.some((o) => o.slug === slug)) return `A bucket with the slug "${slug}" already exists.`;
  return null;
}

/**
 * A bucket's Settings, in the dialog the gear in the bucket rail's header opens: name, slug (with
 * the read-only Id it moves) and description, then the danger zone — Transfer Ownership and
 * Delete. The tables are NOT edited here: each is its own row in the bucket's rail, added with
 * that rail's "+" (Mike, 2026-09-24: "add a gear icon … show the settings in a dialog, remove
 * settings from the tables list"). Save/Cancel are the dialog's button bar; the pane owns the
 * draft and its dirty/validity state.
 */
export function SchemaDefinitionDetail({
  title,
  draft,
  onChange,
  error,
  schema,
  ecosystemRdid,
  renderTransfer,
  onDelete,
}: {
  title: string;
  draft: SchemaDefinitionInput;
  onChange: (next: SchemaDefinitionInput) => void;
  error?: string | null;
  /** The saved bucket, when editing an existing one (null while creating) — carries the id
   *  (the bucket's own rdid) the transfer section below needs; the draft is structure only. */
  schema: SchemaDefinition | null;
  /**
   * The owning Product's scope, as `SchemasPane` itself received it (its `ecosystemId` prop) —
   * passed straight through to the host's transfer renderer, which is the one place that decides
   * whether it's usable as a transfer `currentTarget` (see {@link RenderTransferSection}). Not
   * named `ecosystemId` here: `schema.ecosystemId` already means something else on this file's own
   * row type (a raw uuid) — this is the PANE's scope, not the entity's own foreign key.
   */
  ecosystemRdid?: string;
  /** The host's Transfer Ownership section; omitted ⇒ the bucket offers no transfer. */
  renderTransfer?: RenderTransferSection;
  /** Deletes the bucket; omitted for a built-in (non-`custom`) bucket, which the backend refuses
   *  to delete — so it gets no Delete button rather than one that always fails. */
  onDelete?: () => Promise<void>;
}) {
  return (
    <>
      <DetailSection title={title}>
        <Card>
          <CardContent className="flex flex-col gap-5">
            <Field label="Name" hint="Unique bucket name.">
              <Input
                value={draft.name}
                placeholder="Profile Basics"
                onChange={(e) => onChange({ ...draft, name: e.target.value })}
              />
            </Field>

            <BucketSlugField
              draft={draft}
              onChange={onChange}
              prefix={bucketSlugPrefix(schema?.id, ecosystemRdid)}
            />

            {schema && (
              <Field label="Id" hint="The bucket's rdid — its slug under the ecosystem's storage.">
                <Input value={schema.id} readOnly className="font-mono" />
              </Field>
            )}

            <Field label="Description">
              <Textarea
                rows={2}
                placeholder="What this bucket is for."
                value={draft.description}
                onChange={(e) => onChange({ ...draft, description: e.target.value })}
              />
            </Field>

            {/* Form-level error — not bound to a single field. */}
            <ErrorText error={error} />
          </CardContent>
        </Card>
      </DetailSection>

      {/* Only once the bucket is SAVED — there is nothing to transfer while still drafting one.
          `ecosystemRdid` here is the PANE's scope (see the prop doc above), not derived from
          `schema` itself — `SchemaDefinition` only carries `ecosystemId` as a raw uuid. */}
      {schema &&
        renderTransfer?.({
          entityNoun: "Storage Bucket",
          entityType: "bucket",
          entityId: schema.id,
          // `schema.id`, NOT `schema.name`: the transfer block's `entityLabel` doc says the
          // rdid where the object has one, and a bucket does — `bucket.buckets` is rdid-addressed
          // (backend `src/crud/policy.ts:1066`), so generic CRUD swaps the stored uuid for the rdid
          // in every list/read response (`src/crud/factory.ts:112-116`) and this field IS that rdid.
          // (A row with no `registry.identifiers` entry falls back to its uuid — still an address,
          // still what the confirm dialog should show, and never the display name.) Passing the
          // name made this the one caller contradicting the rule the same branch wrote.
          entityLabel: schema.id,
          ecosystemRdid,
        })}

      {schema && onDelete && (
        <DeleteEntitySection
          entityNoun="Bucket"
          confirmValue={schema.id}
          childEntities="its list of tables (the rows in those tables stay in the ecosystem)"
          onConfirm={onDelete}
        />
      )}
    </>
  );
}
