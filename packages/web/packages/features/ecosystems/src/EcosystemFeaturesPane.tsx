"use client";

import { useCallback, useMemo, useState, type ReactElement } from "react";
import { SlidersHorizontal, Trash2 } from "lucide-react";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { DialogErrorText, ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import {
  useFeatureCatalog,
  useProvisionedFeatures,
  useApplyFeatureChange,
  useRemoveFeature,
  type CatalogFeature,
  type ProvisionedFeature,
} from "@agentic-toolkit/data/ecosystems";
import { FeaturePickerDialog } from "./FeaturePickerDialog";

/**
 * What this ecosystem has been provisioned with, and the one place to change it.
 *
 * An ecosystem is a CONTAINER: it is created empty, and every capability in it got there
 * because someone added it here. So this pane is deliberately plain — a list of what is in
 * the box, a Manage features that opens the picker, and a Remove per row.
 *
 * Remove is not a delete. The backend marks the row removed — which turns the feature's REST
 * routes and MCP tools off — and leaves everything the feature provisioned exactly where it is,
 * so removing a feature by mistake costs nothing but re-adding it. The confirm says so.
 */
export function EcosystemFeaturesPane({
  ecosystemId,
  canEdit = true,
}: {
  /** The ecosystem's rdid or uuid — whatever the host is already addressing it by. */
  ecosystemId: string;
  /** False for a viewer who may see the list but not change it (Add / Remove hidden). */
  canEdit?: boolean;
}): ReactElement {
  const catalogQ = useFeatureCatalog();
  const provisionedQ = useProvisionedFeatures(ecosystemId);
  const apply = useApplyFeatureChange(ecosystemId);
  const remove = useRemoveFeature(ecosystemId);

  const [picking, setPickingRaw] = useState(false);
  // The row awaiting its removal confirm. The whole feature, not just the key, so the
  // dialog can name it after the list has already re-rendered.
  const [removing, setRemoving] = useState<{ key: string; label: string } | null>(null);

  /**
   * Opens/closes the picker, clearing `apply`'s mutation state with it. Without this a failed
   * apply's error survives the close — react-query keeps a mutation's `error` until the next
   * `mutate`/`reset` — so reopening the picker on an unrelated visit would show last visit's
   * failure before the user has done anything this time.
   */
  const setPicking = useCallback(
    (next: boolean) => {
      apply.reset();
      setPickingRaw(next);
    },
    [apply],
  );

  const catalog = useMemo(() => catalogQ.data ?? [], [catalogQ.data]);
  const byKey = useMemo(() => new Map(catalog.map((f) => [f.key, f])), [catalog]);

  // `removed` rows are history — the ledger keeps them so a re-add is an update rather than
  // an insert, and nothing else should ever show them.
  const present = useMemo(
    () => (provisionedQ.data ?? []).filter((f: ProvisionedFeature) => f.state !== "removed"),
    [provisionedQ.data],
  );

  const rows = useMemo(
    () =>
      present
        .map((p: ProvisionedFeature) => ({ provisioned: p, feature: byKey.get(p.featureKey) }))
        // Alphabetical by what the reader sees. A key with no catalog entry (a feature the
        // build has since dropped) still lists, under its key, rather than vanishing from a
        // pane whose whole job is to say what is in the box.
        .sort((a, b) =>
          (a.feature?.label ?? a.provisioned.featureKey).localeCompare(
            b.feature?.label ?? b.provisioned.featureKey,
          ),
        ),
    [present, byKey],
  );

  const presentKeys = useMemo(
    () => new Set<string>(present.map((p: ProvisionedFeature) => p.featureKey)),
    [present],
  );

  const loadError = catalogQ.isError
    ? "Failed to load the feature catalog."
    : provisionedQ.isError
      ? "Failed to load this ecosystem's features."
      : null;

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col gap-4 p-4">
      <div className="flex items-center justify-between gap-3">
        <p className="text-sm text-apt-text-dim">
          The features this ecosystem has been given. Adding one provisions everything it needs.
        </p>
        {canEdit && (
          <Button size="sm" onClick={() => setPicking(true)} disabled={catalogQ.isPending}>
            <SlidersHorizontal className="size-4" aria-hidden />
            Manage features
          </Button>
        )}
      </div>

      <ErrorText error={loadError} />
      {/* Only while the remove confirm is CLOSED: while it's open, the same error renders
          inside that modal (below) — rendering it here too would put it behind the modal's
          backdrop, invisible until the user dismisses the very dialog that caused it. */}
      <ErrorText error={removing == null && remove.isError ? "Failed to remove the feature." : null} />

      {provisionedQ.isPending ? (
        <p className="text-sm text-apt-text-muted">Loading…</p>
      ) : rows.length === 0 ? (
        <EmptyState
          title="No features yet"
          description="This ecosystem is empty. Add the features you want it to carry."
          action={
            canEdit ? (
              <Button size="sm" onClick={() => setPicking(true)}>
                <SlidersHorizontal className="size-4" aria-hidden />
                Manage features
              </Button>
            ) : undefined
          }
        />
      ) : (
        <ul className="divide-y divide-apt-border rounded-lg border border-apt-border">
          {rows.map(({ provisioned: p, feature }) => (
            <FeatureRow
              key={p.featureKey}
              provisioned={p}
              feature={feature}
              canEdit={canEdit}
              onRemove={() =>
                setRemoving({ key: p.featureKey, label: feature?.label ?? p.featureKey })
              }
            />
          ))}
        </ul>
      )}

      <FeaturePickerDialog
        open={picking}
        catalog={catalog}
        alreadyProvisioned={presentKeys}
        busy={apply.isPending}
        error={apply.isError ? "Failed to change the features. Check the list and try again." : null}
        catalogError={catalogQ.isError ? "Failed to load the feature catalog." : null}
        onApply={(change) => apply.mutate(change, { onSuccess: () => setPicking(false) })}
        onCancel={() => setPicking(false)}
      />

      <AlertModal
        open={removing != null}
        title={`Remove ${removing?.label ?? ""}?`}
        description={
          <>
            The feature is hidden and turned off for this ecosystem, including over the REST and
            MCP APIs. Its data is kept, and adding it back restores it.
            {/* `DialogErrorText`, not `ErrorText`: Base UI renders `DialogDescription` as a `<p>`,
                and `ErrorText`'s own `<p role="alert">` cannot legally nest inside one. This is
                also the ONLY place a failed removal is visible while this modal stays open on
                failure — the pane's own `ErrorText` above is behind the backdrop right now. */}
            <DialogErrorText error={remove.isError ? "Failed to remove the feature." : null} />
          </>
        }
        confirmLabel="Remove"
        cancelLabel="Cancel"
        destructive
        busy={remove.isPending}
        onConfirm={() => {
          const key = removing?.key;
          if (!key) return;
          remove.mutate(key, { onSuccess: () => setRemoving(null) });
        }}
        onCancel={() => setRemoving(null)}
      />
    </div>
  );
}

function FeatureRow({
  provisioned,
  feature,
  canEdit,
  onRemove,
}: {
  provisioned: ProvisionedFeature;
  feature: CatalogFeature | undefined;
  canEdit: boolean;
  onRemove: () => void;
}): ReactElement {
  // `provisioning` is shown rather than hidden: provisioning CREATES things and can stop
  // partway, so a row stuck in it is the only evidence that happened.
  const pending = provisioned.state === "provisioning";
  return (
    <li className="flex items-start gap-3 px-3 py-2.5">
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-2">
          <span className="text-sm text-apt-text">{feature?.label ?? provisioned.featureKey}</span>
          {pending && (
            <span className="text-[0.6875rem] tracking-wide text-apt-text-muted uppercase">
              Provisioning
            </span>
          )}
        </div>
        {feature && <p className="text-xs text-apt-text-dim">{feature.description}</p>}
      </div>
      {canEdit && (
        <Button size="sm" variant="ghost" aria-label={`Remove ${feature?.label ?? provisioned.featureKey}`} onClick={onRemove}>
          <Trash2 className="size-4" aria-hidden />
        </Button>
      )}
    </li>
  );
}
