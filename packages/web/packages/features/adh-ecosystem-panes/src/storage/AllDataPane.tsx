"use client";

import { useState } from "react";
import { CrudDataBrowser, type CrudShell } from "@agentic-toolkit/crud";

/**
 * All Data as a member of an ecosystem's Storage rail: the cross-schema CRUD browser.
 *
 * WORKSPACE — `workspace` is the slug whose data this shows. "All data literally shows all data,
 * it should only show data owned by the workspace" (Mike, 2026-09-24): pass it, and the browser
 * lists only that workspace's rows and hides the global catalogs no workspace owns.
 *
 * SCOPE — read this before mounting it on a new host. It passes no `tables` prop, so the browser
 * falls back to its own default: the WHOLE of CRUD_TABLES. That is every schema in
 * allowed-schemas.json — access, billing, monitoring, system, team, usage and the rest — not just
 * the bucket-backed ones the Storage rail is named after. The only narrowing is the browser's own
 * admin-tier filter for a non-admin viewer. `CRUD_TABLES` is bounded at GENERATION time, not per
 * host, so nothing at a mount site trims it: a host that wants a subset has to pass `tables`
 * itself, and a host that mounts this as-is is publishing the full cross-schema browser under
 * whatever its rail calls this row.
 *
 * Selection is LOCAL (component state), not URL-driven, and that is the point of this component
 * rather than a bare `<CrudDataBrowser basePath=…/>`. The enclosing ecosystem URL scheme cedes
 * exactly ONE deep segment to a group member, and the browser needs two (schema ▸ table) — so
 * driving it by URL pushes the standalone all-data route and unmounts the rail the user is
 * standing in. The schema/table rails still publish into the host's merged stack (via `shell`),
 * so a click re-renders in place and the trail stays intact.
 *
 * `shell` is the host's stack adapter. Omit it and the browser uses the crud package's own
 * DefaultCrudShell — correct for a host with no rail chrome of its own to publish into.
 */
export function AllDataPane({ shell, workspace }: { shell?: CrudShell; workspace?: string }) {
  const [schema, setSchema] = useState<string | null>(null);
  const [table, setTable] = useState<string | null>(null);
  return (
    <CrudDataBrowser
      shell={shell}
      workspace={workspace}
      selection={{
        schema,
        table,
        // Changing or clearing the schema resets the table (a different schema has different tables).
        onSelectSchema: (s) => {
          setSchema(s);
          setTable(null);
        },
        onSelectTable: setTable,
      }}
    />
  );
}
