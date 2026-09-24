"use client";

import { buildAvailableTypes, TYPE_SCHEMAS, type AvailableType } from "./available-types";
import { slugifyTableName } from "./schema-model";

const AVAILABLE = buildAvailableTypes();
export const TYPE_BY_ID = new Map(AVAILABLE.map((t) => [t.id, t]));
// Available types grouped by schema, in display order — drives the Add table dialog's picker.
const BY_SCHEMA: Array<{ schema: string; types: AvailableType[] }> = TYPE_SCHEMAS.map(
  (schema) => ({ schema, types: AVAILABLE.filter((t) => t.schema === schema) }),
);

/** Default table name for a type: its bare table name, slugified. */
export function nameForType(typeId: string): string {
  return slugifyTableName(TYPE_BY_ID.get(typeId)?.table ?? "");
}

/** The sql-table catalogue as `<optgroup>`s, one per schema, for a native `<Select>`. */
export function TypeOptions() {
  return (
    <>
      {BY_SCHEMA.map(({ schema, types }) => (
        <optgroup key={schema} label={schema}>
          {types.map((t) => (
            <option key={t.id} value={t.id}>
              {t.label} ({t.table})
            </option>
          ))}
        </optgroup>
      ))}
    </>
  );
}
