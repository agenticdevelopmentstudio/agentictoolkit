"use client";

import { useCallback, useId, useState } from "react";

import { FeatureRequiredError, useEcosystemFeatures } from "@agentic-toolkit/data/ecosystems";
import { useDetailsSection } from "@agentic-toolkit/resource";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Switch } from "@agenticdevelopertoolkit/ui/components/switch";

/**
 * An on/off switch for ONE feature of an ecosystem, as a section of the enclosing
 * {@link DetailsPane}: flipping it is an edit, and the pane's Save adds or removes the feature
 * through the same `apply` the Manage features dialog uses. So there is still one writer of what
 * an ecosystem holds — this switch and the dialog are two views of it — and anything that follows
 * the held features (the realm's gaming mode) follows this switch too.
 *
 * `lockedBy`: a feature that brings this one with it (Gaming brings Gamification). While the
 * ecosystem holds it the switch is on and disabled — taking this one off underneath it is exactly
 * what the backend refuses.
 *
 * `onApplied` runs after a save lands, for a host whose own reads follow the features (the realm
 * config's mode) and need re-reading.
 */
export function FeatureSwitch({
  ecosystemId,
  featureKey,
  label,
  description,
  lockedBy,
  lockedDescription,
  onApplied,
}: {
  ecosystemId?: string;
  featureKey: string;
  label: string;
  description: string;
  lockedBy?: string;
  /** Shown instead of `description` while `lockedBy` holds the switch on. */
  lockedDescription?: string;
  onApplied?: () => void | Promise<void>;
}) {
  const id = useId();
  const features = useEcosystemFeatures(ecosystemId);
  const holdings = features.holdings;
  const held = holdings ? holdings.present.has(featureKey) : null;
  const locked = lockedBy !== undefined && holdings !== undefined && holdings.present.has(lockedBy);
  const unavailableReason = held === false ? features.unavailable.get(featureKey) : undefined;

  // null = untouched: the switch shows what the ecosystem holds.
  const [draft, setDraft] = useState<boolean | null>(null);
  const on = draft ?? held ?? false;
  const dirty = held !== null && draft !== null && draft !== held;

  const save = useCallback(async () => {
    if (!dirty || draft === null) return;
    try {
      await features.apply.mutateAsync(draft ? { add: [featureKey], remove: [] } : { add: [], remove: [featureKey] });
    } catch (err) {
      if (err instanceof FeatureRequiredError) throw err;
      throw new Error(err instanceof Error ? err.message : `Couldn't turn ${label} ${draft ? "on" : "off"}.`);
    }
    setDraft(null);
    // The switch has applied. A follow-up that fails (a re-read, say) must not surface in the
    // bar as the switch failing, which would invite a retry of a change that already landed.
    try {
      await onApplied?.();
    } catch (err) {
      console.error(`[FeatureSwitch] ${featureKey} applied; its follow-up failed:`, err);
    }
  }, [dirty, draft, features.apply, featureKey, label, onApplied]);

  const reset = useCallback(() => setDraft(null), []);
  useDetailsSection({ dirty, canSave: true, save, reset });

  return (
    <div className="flex items-start justify-between gap-6">
      <div className="min-w-0">
        <Label htmlFor={id} className="text-sm font-medium text-apt-text">
          {label}
        </Label>
        <p className="mt-0.5 text-xs text-apt-text-muted">
          {locked && lockedDescription ? lockedDescription : (unavailableReason ?? description)}
        </p>
      </div>
      <Switch
        id={id}
        aria-label={label}
        checked={locked || on}
        disabled={held === null || locked || (unavailableReason !== undefined && !on)}
        onCheckedChange={(next) => setDraft(next)}
      />
    </div>
  );
}
