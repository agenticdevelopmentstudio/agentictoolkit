"use client";

import { useCallback, useState } from "react";
import { TriangleAlert } from "lucide-react";
import { useAction } from "@agentic-toolkit/crud";
import { useResourceList } from "@agentic-toolkit/data";
import { SettingsBody } from "@agentic-toolkit/resource";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { Checkbox } from "@agenticdevelopertoolkit/ui/components/checkbox";
import { Alert, AlertDescription, AlertTitle } from "@agenticdevelopertoolkit/ui/components/alert";
import { errorMessage } from "@agenticdevelopertoolkit/ui/lib/errors";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import {
  EditableList,
  useEditableList,
  type EditableListColumn,
} from "@agenticdevelopertoolkit/ui/blocks";
import {
  personaUserToolsApi,
  type UserActablePersona,
  type UserTool,
} from "@agentic-toolkit/data/personas";
import { sourceLabel } from "./agent-tool-source";

/** The names of the tools currently allowed, in catalog order (the PUT payload shape). */
function allowedNames(tools: UserTool[]): string[] {
  return tools.filter((t) => t.allowed).map((t) => t.toolName);
}

/** The human name a row leads with; displayName falls back to toolName for an uncataloged tool. */
function toolLabel(tool: UserTool): string {
  return tool.displayName || tool.toolName;
}

/**
 * User Settings "Assistants" panel (Layer-2 per-user consent). For each persona an owner has
 * let act FOR the caller (`may_act 'user'`), the caller picks it and toggles — per tool —
 * whether it may invoke that tool on their behalf, with an all-on / all-off pair on the table's
 * bar. Default
 * off: an untoggled tool is not allowed.
 *
 * Every change replaces the caller's whole allowed set (`PUT user-tools`) OPTIMISTICALLY —
 * the checklist flips instantly and reverts if the request rejects, reconciling from the
 * server's returned view on success. Backend enforces the actual permission (403/400); the
 * panel just surfaces the error.
 *
 * Both reads are CACHED, and each assistant's tool list under its own key — so flipping back to
 * an assistant you looked at a moment ago shows its checklist immediately rather than a spinner.
 */
export function AssistantsPanel() {
  const [personaId, setPersonaId] = useState("");
  const { busy, error, run } = useAction();

  // The assistants that may act for the caller. Caller-scoped, so one entry serves every mount.
  const { items: personas, error: personasError } = useResourceList<UserActablePersona>(
    "personas:actable-for-me",
    personaUserToolsApi.listActable,
  );

  // The selected assistant's tools, keyed BY assistant. That key is what replaces the monotonic
  // load token this panel used to carry: a response can only ever land on the entry it was read
  // for, so an older in-flight `listTools()` cannot write into whichever assistant is now picked.
  // No selection reads nothing.
  const loadTools = useCallback(
    () => (personaId ? personaUserToolsApi.listTools(personaId) : Promise.resolve([] as UserTool[])),
    [personaId],
  );
  const {
    items: tools,
    error: loadError,
    setItems: setTools,
  } = useResourceList<UserTool>(`persona:${personaId}:user-tools`, loadTools);

  // Replace the whole tool view optimistically, PUT the derived allowed set, reconcile from
  // the server's returned view on success, and restore the prior view on failure.
  //
  // The token guard is gone for the same reason: `setTools` is bound to the cache key of the
  // render that produced it, so a reconcile or a revert that resolves after a switch writes into
  // the assistant it was ABOUT — which is both correct for that assistant and invisible to the
  // one now on screen.
  const applyAllowed = useCallback(
    (prev: UserTool[], optimistic: UserTool[]) => {
      const id = personaId;
      setTools(optimistic);
      void run(async () => {
        try {
          setTools(await personaUserToolsApi.setAllowed(id, allowedNames(optimistic)));
        } catch (e) {
          setTools(prev);
          throw e;
        }
      });
    },
    [personaId, run, setTools],
  );

  function toggleTool(tool: UserTool, allowed: boolean) {
    if (!tools) return;
    applyAllowed(
      tools,
      tools.map((t) => (t.toolName === tool.toolName ? { ...t, allowed } : t)),
    );
  }

  /** All on / All off — over the rows ON SCREEN. With a search typed, the user is looking at a
   *  narrowed list and the button sits right above it; flipping tools the search had hidden too
   *  granted (or revoked) permissions they never saw. Unfiltered, the shown rows are all of them. */
  function setAll(allowed: boolean) {
    if (!tools) return;
    const shown = new Set(list.rows.map((t) => t.toolName));
    applyAllowed(
      tools,
      tools.map((t) => (shown.has(t.toolName) ? { ...t, allowed } : t)),
    );
  }

  // The same table admin's Users page draws, with selection OFF: the one control a row carries is
  // its own allow switch — inherently per-row state — and "All on / All off" act on every SHOWN row, so
  // there is nothing for a tick box to select FOR. Provenance used to be bespoke group headings;
  // it is now the Source column the list OPENS sorted by — the same built-ins-then-each-source
  // reading, but one the user can re-sort or search. `sourceLabel` stays the one home of the
  // "only a genuinely null source is Built-in" rule.
  const columns: EditableListColumn<UserTool>[] = [
    {
      key: "tool",
      header: "Tool",
      width: "14rem",
      value: toolLabel,
      render: (tool) => (
        <span className="truncate font-medium text-apt-text">{toolLabel(tool)}</span>
      ),
    },
    {
      key: "description",
      header: "Description",
      value: (tool) => tool.description,
      render: (tool) =>
        tool.description ? (
          <span className="truncate text-xs text-apt-text-muted" title={tool.description}>
            {tool.description}
          </span>
        ) : (
          <span className="text-apt-text-dim">—</span>
        ),
    },
    {
      // The raw tool name is demoted to a mono caption, never hidden — it is what an audit log
      // or an error message will call the tool.
      key: "name",
      header: "Name",
      width: "12rem",
      value: (tool) => tool.toolName,
      render: (tool) => (
        <span className="truncate font-mono text-xs text-apt-text-dim" title={tool.toolName}>
          {tool.toolName}
        </span>
      ),
    },
    {
      key: "source",
      header: "Source",
      width: "10rem",
      value: (tool) => sourceLabel(tool.source),
    },
    {
      key: "enabled",
      header: "Enabled",
      width: "6rem",
      resizable: false,
      // Sortable ("what have I allowed?" is a real question) but not searchable: typing "on"
      // into the search box must not match every allowed row.
      value: (tool) => (tool.allowed ? "On" : "Off"),
      searchable: false,
      render: (tool) => (
        <Checkbox
          checked={tool.allowed}
          disabled={busy}
          onCheckedChange={(checked) => toggleTool(tool, checked)}
          aria-label={`Allow ${toolLabel(tool)}`}
        />
      ),
    },
  ];

  const list = useEditableList<UserTool>({
    rows: tools ?? undefined,
    getRowId: (tool) => tool.toolName,
    columns,
    initialSort: { key: "source", dir: "asc" },
  });

  // Keyed on the SHOWN rows: a search that matches nothing leaves the bulk buttons nothing to act on.
  const noTools = list.rows.length === 0;

  return (
    <SettingsBody width="full">
      <p className="text-sm text-apt-text-muted">
        Control what each assistant may do on your behalf. Every tool is off until you allow it
        here.
      </p>

      {/* The FAILURE is read first: a failed read leaves the rows null, so testing for null
          first would leave the panel saying "Loading…" over a read that has already given up. */}
      {personasError !== null ? (
        // The same load-failure card the settings tables draw for their own failed read, so a
        // panel that fails BEFORE its table exists does not look like a different site's error.
        <Alert variant="error">
          <TriangleAlert />
          <AlertTitle>Couldn&apos;t load your assistants</AlertTitle>
          <AlertDescription>{errorMessage(personasError)}</AlertDescription>
        </Alert>
      ) : personas === null ? (
        <p className="text-sm text-apt-text-muted">Loading…</p>
      ) : personas.length === 0 ? (
        <p className="text-sm text-apt-text-muted">
          No assistants can act for you yet. When an assistant is granted leave to act on your
          behalf, it will appear here.
        </p>
      ) : (
        <div className="flex flex-col gap-4">
          {/* A labelled field ABOVE the table, not in its bar: it picks WHICH list is shown, so it
              is not an action on the rows. Capped so the select does not stretch across a
              full-width pane. */}
          <div className="max-w-sm">
            <Field label="Assistant">
              <Select
                value={personaId}
                onChange={(e) => {
                  // A search typed for one assistant's tools means nothing against another's, and
                  // left in place it silently hides rows — and narrows what All on/off acts on.
                  list.setSearch("");
                  setPersonaId(e.target.value);
                }}
              >
                <option value="">Choose an assistant…</option>
                {personas.map((persona) => (
                  <option key={persona.id} value={persona.id}>
                    {persona.name}
                  </option>
                ))}
              </Select>
            </Field>
          </div>

          {/* The write's failure only — a failed tool READ is the table's own error state, which
              replaces the rows rather than leaving an empty-state claim the read cannot make. */}
          <ErrorText error={error} />

          {personaId === "" ? (
            <p className="text-sm text-apt-text-muted">
              Pick an assistant to review what it may do for you.
            </p>
          ) : (
            <EditableList
              list={list}
              ariaLabel="Assistant tools"
              selectable={false}
              // A failed read leaves the rows null too, and the error state already says why — so
              // the table must not go on claiming the list is still on its way.
              loading={tools === null && !loadError}
              error={loadError}
              errorTitle="Couldn't load this assistant's tools"
              columnWidthsKey="settings-assistant-tools"
              describeRow={toolLabel}
              searchPlaceholder="Tool, name or source"
              emptyLabel="This assistant has no tools you can allow."
              emptyFilteredLabel="No tools match this search."
              actions={
                <>
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    disabled={busy || noTools}
                    onClick={() => setAll(true)}
                  >
                    {list.filtered ? "All shown on" : "All on"}
                  </Button>
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    disabled={busy || noTools}
                    onClick={() => setAll(false)}
                  >
                    {list.filtered ? "All shown off" : "All off"}
                  </Button>
                </>
              }
            />
          )}
        </div>
      )}
    </SettingsBody>
  );
}

