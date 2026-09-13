"use client";

import { useCallback, useEffect, useState } from "react";
import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";

import type { EndpointView } from "@agentic-toolkit/data/monitored-sites";
import {
  ENDPOINT_KINDS,
  createEndpoint,
  deleteEndpoint,
  listEndpoints,
  updateEndpoint,
} from "@agentic-toolkit/data/monitored-sites";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Checkbox } from "@agenticdevelopertoolkit/ui/components/checkbox";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { TopicSelectHint } from "@agenticdevelopertoolkit/ui/blocks";
import { DetailFooter, MasterDetailLayout, useRecordAffordance } from "@agentic-toolkit/resource";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";

/**
 * Topic/details list of a single site's endpoints: pick an endpoint on the
 * left, edit only its settings on the right. Endpoints are independent entities
 * (own CRUD), so each persists via its own Save/Delete rather than the parent
 * site's footer.
 */
export function EndpointsEditor({
  siteId,
  workspaceSlug,
}: {
  siteId: string;
  /** Pins every op to the WORKSPACE'S owning principal (backend `?workspace=`). */
  workspaceSlug?: string;
}) {
  const renderRecordAffordance = useRecordAffordance();
  const [endpoints, setEndpoints] = useState<EndpointView[] | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      setEndpoints(await listEndpoints(siteId, { workspace: workspaceSlug }));
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "endpoints-editor", step: "load" });
      setLoadError(err instanceof Error ? err.message : "Failed to load endpoints.");
    }
  }, [siteId, workspaceSlug]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const selected = selectedId
    ? (endpoints?.find((e) => e.id === selectedId) ?? null)
    : null;

  return (
    <>
      <ErrorText error={loadError} className="mb-3" />

      <div className="mb-3 flex justify-end">
        {renderRecordAffordance?.({
          path: "/monitoring/endpoints",
          pathValues: {},
          queryValues: { siteId },
          title: "Monitoring endpoints API",
        })}
      </div>

      <MasterDetailLayout
        // NESTED: this whole editor is rendered inside a SITE's detail, whose own Save/Cancel bar
        // is already the pane's. Its endpoint bar therefore stays here, above the endpoint list it
        // acts on, instead of hoisting into the host's single toolbar slot and stacking under the
        // site's — "New endpoint" and a Delete in the page header, for a list two scroll regions
        // down.
        nested
        items={(endpoints ?? []).map((e) => ({
          id: e.id,
          label: e.url || "(no url)",
          sublabel: `${e.kind} · ${e.expectedStatus}${e.isActive ? "" : " · paused"}`,
        }))}
        selectedId={selectedId}
        onSelect={(id) => {
          setCreating(false);
          setSelectedId(id);
        }}
        onNew={() => {
          setSelectedId(null);
          setCreating(true);
        }}
        newLabel="New endpoint"
        emptyLabel={endpoints === null ? "Loading…" : "No endpoints yet."}
      >
        {creating || selected ? (
          <EndpointDetail
            key={creating ? "__new__" : selected!.id}
            siteId={siteId}
            workspaceSlug={workspaceSlug}
            initial={creating ? null : selected}
            onSaved={async (id) => {
              await refresh();
              setCreating(false);
              setSelectedId(id);
            }}
            onDeleted={async () => {
              await refresh();
              setSelectedId(null);
            }}
            onCancel={() => {
              setCreating(false);
              setSelectedId(null);
            }}
          />
        ) : endpoints === null ? (
          <EmptyState title="Loading…" />
        ) : (
          <TopicSelectHint title="Select an endpoint to edit, or add a new one." />
        )}
      </MasterDetailLayout>
    </>
  );
}

interface Draft {
  url: string;
  kind: string;
  expectedStatus: string;
  checkIntervalSeconds: string;
  isActive: boolean;
}

function blank(): Draft {
  return {
    url: "",
    kind: ENDPOINT_KINDS[0],
    expectedStatus: "200",
    checkIntervalSeconds: "60",
    isActive: true,
  };
}

function toDraft(e: EndpointView): Draft {
  return {
    url: e.url,
    kind: e.kind,
    expectedStatus: String(e.expectedStatus),
    checkIntervalSeconds: String(e.checkIntervalSeconds),
    isActive: e.isActive,
  };
}

function EndpointDetail({
  siteId,
  workspaceSlug,
  initial,
  onSaved,
  onDeleted,
  onCancel,
}: {
  siteId: string;
  workspaceSlug?: string;
  initial: EndpointView | null;
  onSaved: (id: string) => Promise<void>;
  onDeleted: () => Promise<void>;
  onCancel: () => void;
}) {
  const base = initial ? toDraft(initial) : blank();
  const [draft, setDraft] = useState<Draft>(base);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const dirty =
    draft.url.trim() !== base.url.trim() ||
    draft.kind !== base.kind ||
    draft.expectedStatus.trim() !== base.expectedStatus.trim() ||
    draft.checkIntervalSeconds.trim() !== base.checkIntervalSeconds.trim() ||
    draft.isActive !== base.isActive;

  function set<K extends keyof Draft>(key: K, value: Draft[K]) {
    setDraft((d) => ({ ...d, [key]: value }));
    setError(null);
  }

  function validate(): string | null {
    if (!draft.url.trim()) return "URL is required.";
    const status = parseInt(draft.expectedStatus, 10);
    if (!Number.isFinite(status) || status < 100 || status > 599)
      return "Expected status must be a valid HTTP status code.";
    const interval = parseInt(draft.checkIntervalSeconds, 10);
    if (!Number.isFinite(interval) || interval <= 0)
      return "Check interval must be a positive number of seconds.";
    return null;
  }

  async function handleSave() {
    const problem = validate();
    if (problem) {
      setError(problem);
      return;
    }
    setSaving(true);
    try {
      const payload = {
        url: draft.url.trim(),
        kind: draft.kind,
        expectedStatus: parseInt(draft.expectedStatus, 10),
        checkIntervalSeconds: parseInt(draft.checkIntervalSeconds, 10),
        isActive: draft.isActive,
      };
      const saved = initial
        ? await updateEndpoint(initial.id, payload, { workspace: workspaceSlug })
        : await createEndpoint(siteId, payload, { workspace: workspaceSlug });
      await onSaved(saved.id);
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "endpoints-editor", step: "save" });
      setError(err instanceof Error ? err.message : "Failed to save endpoint.");
    } finally {
      setSaving(false);
    }
  }

  function handleCancel() {
    if (dirty) setDraft(base);
    else onCancel();
  }

  async function handleDelete() {
    if (!initial) return;
    if (!confirm("Delete this endpoint?")) return;
    setDeleting(true);
    try {
      await deleteEndpoint(initial.id, { workspace: workspaceSlug });
      await onDeleted();
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "endpoints-editor", step: "delete" });
      setError(err instanceof Error ? err.message : "Failed to delete endpoint.");
      setDeleting(false);
    }
  }

  return (
    <>
      <Card>
        <CardContent className="flex flex-col gap-5">
          <div className="flex flex-col gap-2">
            <Label htmlFor="ep-url">URL</Label>
            <Input
              id="ep-url"
              placeholder="https://example.com/health"
              value={draft.url}
              onChange={(e) => set("url", e.target.value)}
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
            />
          </div>

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div className="flex flex-col gap-2">
              <Label htmlFor="ep-kind">Kind</Label>
              <Select
                id="ep-kind"
                value={draft.kind}
                onChange={(e) => set("kind", e.target.value)}
              >
                {ENDPOINT_KINDS.map((k) => (
                  <option key={k} value={k}>
                    {k}
                  </option>
                ))}
              </Select>
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="ep-status">Expected status</Label>
              <Input
                id="ep-status"
                type="number"
                min={100}
                max={599}
                value={draft.expectedStatus}
                onChange={(e) => set("expectedStatus", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="ep-interval">Check interval (seconds)</Label>
              <Input
                id="ep-interval"
                type="number"
                min={1}
                value={draft.checkIntervalSeconds}
                onChange={(e) => set("checkIntervalSeconds", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="ep-active">Status</Label>
              <label
                htmlFor="ep-active"
                className="flex h-9 cursor-pointer items-center gap-3 text-sm text-apt-text"
              >
                <Checkbox
                  id="ep-active"
                  checked={draft.isActive}
                  onCheckedChange={(value) => set("isActive", value)}
                />
                <span>{draft.isActive ? "Active" : "Paused"}</span>
              </label>
            </div>
          </div>

          <ErrorText error={error} />
        </CardContent>
      </Card>

      <DetailFooter
        dirty={dirty}
        saving={saving}
        onCancel={handleCancel}
        onSave={handleSave}
        saveLabel={initial ? "Save" : "Create"}
        leading={
          initial ? (
            <Button variant="destructive" onClick={handleDelete} disabled={deleting || saving}>
              {deleting ? "Deleting…" : "Delete"}
            </Button>
          ) : undefined
        }
      />
    </>
  );
}
