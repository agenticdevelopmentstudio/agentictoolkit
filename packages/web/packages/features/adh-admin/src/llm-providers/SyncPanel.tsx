"use client";

import { RefreshCw } from "lucide-react";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
} from "@agenticdevelopertoolkit/ui/components/card";
import { useSyncStatus, useRunSync } from "../api/llm-providers";
import { formatRelativeTime, finiteCount } from "./sync-format";

/**
 * Operator panel for the provider-template catalog sync: the last run per
 * upstream source (models.dev / OpenRouter / arena) plus a "Sync now" button
 * that forces a round immediately. Reads `useSyncStatus`; the button drives
 * `useRunSync`, which invalidates both the status and the template list so the
 * table reflects any synced rows the round upserts.
 */
export function SyncPanel() {
  const { data, isLoading } = useSyncStatus();
  const runSync = useRunSync();
  const sources = data?.sources ?? [];

  return (
    <Card className="gap-4 py-4">
      <CardHeader className="flex-row items-start justify-between gap-2">
        <div className="flex flex-col gap-1.5">
          <CardTitle>Catalog sync</CardTitle>
          <CardDescription>
            The model catalog is refreshed from upstream sources on a schedule.
          </CardDescription>
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={() => runSync.mutate()}
          disabled={runSync.isPending}
        >
          <RefreshCw
            data-icon="inline-start"
            className={runSync.isPending ? "animate-spin" : undefined}
          />
          {runSync.isPending ? "Syncing…" : "Sync now"}
        </Button>
      </CardHeader>
      <CardContent className="flex flex-col gap-2 text-sm">
        {isLoading && <span className="text-apt-text-dim">Loading sync status…</span>}
        {!isLoading && sources.length === 0 && (
          <span className="text-apt-text-dim">No sync has run yet.</span>
        )}
        {sources.map((run) => (
          <div key={run.source} className="flex flex-wrap items-center gap-2">
            <span className="font-mono text-apt-text">{run.source}</span>
            <Badge variant={run.ok ? "success" : "error"}>{run.ok ? "ok" : "failed"}</Badge>
            <span className="text-apt-text-muted">
              · {formatRelativeTime(run.lastRunAt)} · {finiteCount(run.detail?.modelsUpserted)}{" "}
              upserted
            </span>
          </div>
        ))}
        {runSync.isError && <ErrorText error="Couldn’t start the sync." />}
      </CardContent>
    </Card>
  );
}
