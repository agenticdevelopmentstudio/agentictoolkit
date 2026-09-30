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
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Checkbox } from "@agenticdevelopertoolkit/ui/components/checkbox";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { TopicSelectHint } from "@agenticdevelopertoolkit/ui/blocks";
import { MasterDetailLayout, useMasterDetailForm } from "@agentic-toolkit/resource";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";

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

function normalize(d: Draft): Draft {
  return {
    ...d,
    url: d.url.trim(),
    expectedStatus: d.expectedStatus.trim(),
    checkIntervalSeconds: d.checkIntervalSeconds.trim(),
  };
}

function differs(a: Draft, b: Draft): boolean {
  return JSON.stringify(normalize(a)) !== JSON.stringify(normalize(b));
}

function validate(draft: Draft): string | null {
  if (!draft.url.trim()) return "URL is required.";
  const status = parseInt(draft.expectedStatus, 10);
  if (!Number.isFinite(status) || status < 100 || status > 599)
    return "Expected status must be a valid HTTP status code.";
  const interval = parseInt(draft.checkIntervalSeconds, 10);
  if (!Number.isFinite(interval) || interval <= 0)
    return "Check interval must be a positive number of seconds.";
  return null;
}

function toPayload(d: Draft) {
  return {
    url: d.url,
    kind: d.kind,
    expectedStatus: parseInt(d.expectedStatus, 10),
    checkIntervalSeconds: parseInt(d.checkIntervalSeconds, 10),
    isActive: d.isActive,
  };
}

/**
 * Topic/details list of a single site's endpoints: pick an endpoint on the
 * left, edit only its settings on the right. Endpoints are independent entities
 * (own CRUD), so each persists via its own Save/Delete rather than the parent
 * site's bar.
 *
 * ONE bar: New / Delete / Cancel / Save and the endpoints API button all live in this list's own
 * (nested) button bar. It used to carry two — an API row above the list and a Save/Cancel footer
 * under the form — so the endpoint's actions were split across the top and the bottom of a list
 * that scrolled between them.
 */
export function EndpointsEditor({
  siteId,
  workspaceSlug,
}: {
  siteId: string;
  /** Pins every op to the WORKSPACE'S owning principal (backend `?workspace=`). */
  workspaceSlug?: string;
}) {
  const ws = { workspace: workspaceSlug };
  const [endpoints, setEndpoints] = useState<EndpointView[] | null>(null);
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

  const form = useMasterDetailForm<EndpointView, Draft>({
    items: endpoints,
    getId: (e) => e.id,
    blank,
    toInput: toDraft,
    validate,
    differs,
    normalize,
    create: (input) => createEndpoint(siteId, toPayload(input), ws),
    update: (id, input) => updateEndpoint(id, toPayload(input), ws),
    remove: (e) => deleteEndpoint(e.id, ws),
    confirmDelete: (e) => `Delete the endpoint "${e.url || "(no url)"}"?`,
    refresh,
    createLabel: "New endpoint",
  });

  return (
    <>
      <ErrorText error={loadError} className="mb-3" />
      {/* A fixed height, so this list never grows the site pane it sits in: the endpoint list and
          the form each scroll inside it (MasterDetailLayout's aside/section do the scrolling). */}
      <div className="flex h-[28rem] min-h-0 flex-col rounded-md border border-apt-border">
        <MasterDetailLayout
          // NESTED: this whole editor is rendered inside a SITE's detail, whose own Save/Cancel bar
          // is already the pane's. Its endpoint bar therefore stays here, above the endpoint list it
          // acts on, instead of hoisting into the host's single toolbar slot and stacking under the
          // site's — "New endpoint" and a Delete in the page header, for a list two scroll regions
          // down.
          nested
          actions={form.actions}
          api={{
            // The item route has no GET; its PUT is what this form's Save calls.
            method: form.selectedId ? "PUT" : "GET",
            path: form.selectedId ? "/monitoring/endpoints/{id}" : "/monitoring/endpoints",
            pathValues: form.selectedId ? { id: form.selectedId } : {},
            queryValues: form.selectedId ? undefined : { siteId },
            title: "Monitoring endpoints API",
          }}
          items={(endpoints ?? []).map((e) => ({
            id: e.id,
            label: e.url || "(no url)",
            sublabel: `${e.kind} · ${e.expectedStatus}${e.isActive ? "" : " · paused"}`,
          }))}
          selectedId={form.selectedId}
          onSelect={form.select}
          emptyLabel={endpoints === null ? "Loading…" : "No endpoints yet."}
        >
          {form.draft ? (
            <EndpointFields
              key={form.detailKey}
              draft={form.draft}
              onChange={form.onChange}
              error={form.error}
            />
          ) : endpoints === null ? (
            <EmptyState title="Loading…" />
          ) : (
            <TopicSelectHint title="Select an endpoint to edit, or add a new one." />
          )}
        </MasterDetailLayout>
      </div>
    </>
  );
}

function EndpointFields({
  draft,
  onChange,
  error,
}: {
  draft: Draft;
  onChange: (next: Draft) => void;
  error: string | null;
}) {
  function set<K extends keyof Draft>(key: K, value: Draft[K]) {
    onChange({ ...draft, [key]: value });
  }

  return (
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
            <Select id="ep-kind" value={draft.kind} onChange={(e) => set("kind", e.target.value)}>
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
  );
}
