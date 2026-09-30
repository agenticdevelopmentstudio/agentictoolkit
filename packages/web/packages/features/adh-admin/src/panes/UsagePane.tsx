"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import { useRouter } from "next/navigation";
import { Info, Pencil, ShieldCheck, ShieldOff, TriangleAlert } from "lucide-react";
import {
  useUsageEnforcement,
  useSetEnforcement,
  useRateLimitTiers,
  useUpdateRateLimitTier,
  type RateLimitTier,
  type UsageEnforcement,
} from "../api/usage";
import {
  NUMERIC_FIELDS,
  NUMERIC_SPEC,
  bodyFrom,
  draftFrom,
  isTierFormDirty,
  tierChanges,
  tierFormBlockedReason,
  type NumericField,
  type TierDraft,
} from "../usage/tier-form";
import { errorMessage } from "@agenticdevelopertoolkit/ui/lib/errors";
import { useAction } from "@agenticdevelopertoolkit/ui/hooks/useAction";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { Switch } from "@agenticdevelopertoolkit/ui/components/switch";
import { Checkbox } from "@agenticdevelopertoolkit/ui/components/checkbox";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import {
  Alert,
  AlertTitle,
  AlertDescription,
} from "@agenticdevelopertoolkit/ui/components/alert";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { DialogActions } from "@agenticdevelopertoolkit/ui/components/dialog-actions";
import { UnsavedChangesGuard } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-guard";
import { Field, ProgressModal } from "@agenticdevelopertoolkit/ui/blocks";
import { FeatureTitle } from "@agentic-toolkit/resource";
import {
  EditableList,
  useBatchRun,
  useEditableList,
  type EditableListColumn,
  type EditableListFacet,
} from "../components/editable-list";

// The metering console. A metered cap refuses a request only when TWO switches agree — the tier's
// own `Enforced` box and the one global switch above all of them — so both live on this page, and
// the page says which one is currently the reason nothing is being refused. The environment-only
// pricing knobs are shown read-only beside them: they decide what enforcement CHARGES the moment it
// starts biting, and arming a cap without seeing them is arming a cap of unknown price.
//
// The tiers table is a read-only editable list now. It used to be eight inline-editable cells and a
// per-row commit control, which meant arming three tiers was three separate hovers, three separate
// ticks and three separate saves — and that the nine values of one tier were spread across a row
// wide enough to scroll, so the field being typed and the field it has to agree with (a refill
// rate and its interval) were rarely on screen together. Editing happens in a dialog over the one
// selected row; Arm and Disarm act on the whole selection from the bar.

/** Module-level so the arm/disarm runs aren't handed a new key on every render. */
const TIERS_KEY = ["admin", "usage", "tiers"];

/** How a tier's own switch reads in the table, and in the Enforced facet. */
const enforcedLabel = (tier: RateLimitTier): string =>
  tier.quotaEnforced ? "Armed" : "Observe only";

/**
 * What a caller on this tier would actually be REFUSED with right now, from the persisted row and
 * the effective switch. Both refusals ride the same switch, so a tier whose four quotas are all
 * blank can only ever produce 429s from its rate bucket — the seeded state, and the single most
 * misleading thing about arming a tier if the page doesn't say it.
 */
function refusalOf(
  tier: RateLimitTier,
  on: boolean,
): { label: string; variant: "neutral" | "accent" | "orange"; title: string } {
  if (!on) {
    return {
      label: "nothing",
      variant: "neutral",
      title: "The global switch is off — usage is recorded but never refused",
    };
  }
  if (!tier.quotaEnforced) {
    return {
      label: "nothing",
      variant: "neutral",
      title: "This tier is observe-only — arm it from the bar to make its caps bite",
    };
  }
  const capped =
    tier.quotaRequests !== null ||
    tier.quotaBytes !== null ||
    tier.quotaTokens !== null ||
    tier.quotaCostMicros !== null;
  return capped
    ? {
        label: "429 + 402",
        variant: "orange",
        title: "Over the rate bucket → 429; over a period quota → 402",
      }
    : {
        label: "429 only",
        variant: "accent",
        title: "Every period quota is blank (uncapped), so only the rate bucket can refuse",
      };
}

export function UsagePane({ help }: { help?: ReactNode } = {}) {
  const router = useRouter();
  const enforcement = useUsageEnforcement();
  const { data, isLoading, error } = useRateLimitTiers();
  const updateTier = useUpdateRateLimitTier();

  // The dialog's TARGET and its OPENNESS are separate state, so closing does not wipe a
  // half-typed draft: nine numeric fields is a lot to lose to a stray Escape, and the page's
  // navigation guard needs something to still be dirty about once the dialog is shut. The draft
  // resets only when the dialog is pointed at a DIFFERENT tier (the key below changes).
  const [editingId, setEditingId] = useState<string | null>(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [dialogDirty, setDialogDirty] = useState(false);

  const armRun = useBatchRun({ invalidateKey: TIERS_KEY, successMessage: "saved" });

  // Resolved from the LIVE rows, never captured at click time: a saved tier refetches, and a
  // dialog still comparing against the row as it looked before the save reads as permanently
  // dirty — which would leave the navigation guard armed over an edit that already landed.
  const editing = useMemo(
    () => (data ?? []).find((tier) => tier.id === editingId) ?? null,
    [data, editingId],
  );

  const enforcing = enforcement.data?.enabled ?? false;

  /** One read-only numeric cell — sorted by the stored number, shown as ∞ when uncapped. */
  const numericColumn = useCallback((field: NumericField): EditableListColumn<RateLimitTier> => {
    const spec = NUMERIC_SPEC[field];
    return {
      key: field,
      header: spec.header,
      width: spec.width,
      align: "end",
      // The NUMBER, not its text: a column sorted by the rendered string puts 1000 before 200.
      // `null` is missing, which the shared comparator sorts last in both directions — the right
      // answer here, since an uncapped tier is not "the smallest cap".
      value: (tier) => tier[field],
      render: (tier) => {
        const n = tier[field];
        return (
          <span className="tabular-nums text-sm text-apt-text" title={spec.title}>
            {n === null ? <span className="text-apt-text-dim">∞</span> : n.toLocaleString()}
          </span>
        );
      },
    };
  }, []);

  const columns = useMemo<EditableListColumn<RateLimitTier>[]>(
    () => [
      {
        key: "tier",
        header: "Tier",
        // Searched by slug AND name together, so typing either finds the row.
        value: (tier) => `${tier.slug} ${tier.name}`,
        render: (tier) => (
          <div className="flex items-center gap-2 overflow-hidden">
            <span className="font-mono text-sm text-apt-text">{tier.slug}</span>
            <span className="truncate text-sm text-apt-text-muted">{tier.name}</span>
            {tier.isDefault && <Badge variant="accent">default</Badge>}
            {!tier.isActive && <Badge variant="neutral">inactive</Badge>}
          </div>
        ),
      },
      {
        key: "quotaEnforced",
        header: "Enforced",
        width: "8rem",
        value: enforcedLabel,
        render: (tier) => (
          <Badge
            variant={tier.quotaEnforced ? "orange" : "neutral"}
            title="Whether this tier's caps are armed (they still need the global switch above)"
          >
            {tier.quotaEnforced ? "armed" : "observe"}
          </Badge>
        ),
      },
      {
        key: "refuses",
        header: "Refuses",
        width: "8.5rem",
        value: (tier) => refusalOf(tier, enforcing).label,
        render: (tier) => {
          const refusal = refusalOf(tier, enforcing);
          return (
            <Badge variant={refusal.variant} title={refusal.title}>
              {refusal.label}
            </Badge>
          );
        },
      },
      ...NUMERIC_FIELDS.map(numericColumn),
    ],
    [enforcing, numericColumn],
  );

  const facets = useMemo<EditableListFacet<RateLimitTier>[]>(
    () => [{ id: "enforced", label: "Enforced", valuesOf: (tier) => [enforcedLabel(tier)] }],
    [],
  );

  const list = useEditableList<RateLimitTier>({
    rows: data,
    getRowId: (tier) => tier.id,
    columns,
    facets,
    // The default tier first — it is what every unassigned principal falls to — then by slug.
    // Expressed as a sort on a column the operator can re-click, rather than a fixed pre-sort they
    // cannot undo.
    initialSort: { key: "tier", dir: "asc" },
  });

  const selected = list.selectedRows;

  /**
   * Arm or disarm the selection, skipping the rows already in that state.
   *
   * A no-op PUT is a real write to a table every request reads, and a run that reports "saved five"
   * when it changed two is a number the operator cannot act on.
   */
  const setEnforced = (quotaEnforced: boolean) => {
    const changing = selected.filter((tier) => tier.quotaEnforced !== quotaEnforced);
    void armRun.run(
      changing.map((tier) => ({ id: tier.id, label: tier.slug })),
      (item) => updateTier.mutateAsync({ id: item.id, changes: { quotaEnforced } }),
    );
  };
  const wouldChange = (quotaEnforced: boolean) =>
    selected.some((tier) => tier.quotaEnforced !== quotaEnforced);

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <FeatureTitle
        title="Usage Limits"
        api={{
          method: "GET",
          path: "/usage/enforcement",
          pathValues: {},
          title: "Usage enforcement API",
        }}
        help={help}
      />
      <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto px-6 pb-8 pt-2">
        <p className="mb-6 max-w-3xl px-2 text-sm text-apt-text-muted">
          Every authenticated request and every LLM turn is metered regardless of what is set here.
          A cap only <em>refuses</em> anything when both switches agree: the global switch below, and
          the tier&apos;s own <span className="font-mono">Enforced</span> state.
        </p>

        {enforcement.error && (
          <Alert variant="error" className="mb-6">
            <TriangleAlert />
            <AlertTitle>Couldn&apos;t read the enforcement switch</AlertTitle>
            <AlertDescription>{errorMessage(enforcement.error)}</AlertDescription>
          </Alert>
        )}

        {enforcement.data && <GlobalSwitchCard state={enforcement.data} />}
        {enforcement.data && <KnobsPanel state={enforcement.data} />}
        {enforcement.data && <VisitorFloorPanel state={enforcement.data} />}

        <h2 className="mb-2 px-2 text-lg font-semibold text-apt-text">Tiers</h2>
        <p className="mb-4 max-w-3xl px-2 text-sm text-apt-text-muted">
          One row per <span className="font-mono">usage.rate_limit_tiers</span> tier. A principal with
          no explicit assignment falls to the default tier. Blank quota means <em>uncapped</em> (shown
          as ∞), not zero — a tier with all four quotas blank can only ever refuse with a 429 from its
          rate bucket, however armed it is.
        </p>

        {/* No New and no Delete, by design: dropping a tier would orphan its
            `usage.principal_tiers` assignments, and deleting the `is_default` row makes every
            subsequent resolve throw NoDefaultTierError — platform-wide. Same reason
            `isDefault`/`isActive` are read-only badges: a write here could leave zero default rows.
            Tier lifecycle stays in All-Data, under generic CRUD. */}
        <EditableList<RateLimitTier>
          list={list}
          ariaLabel="Rate-limit tiers"
          loading={isLoading}
          error={error}
          errorTitle="Couldn't load the tiers"
          columnWidthsKey="admin-usage-tiers"
          describeRow={(tier) => tier.slug}
          searchPlaceholder="Tier slug or name"
          emptyLabel="No rate-limit tiers."
          emptyFilteredLabel="No tiers match these filters."
          actions={
            <>
              {/* One row, or nothing: the dialog holds ONE tier's nine values. */}
              <Button
                size="sm"
                variant="ghost"
                disabled={selected.length !== 1}
                onClick={() => {
                  setEditingId(selected[0]!.id);
                  setDialogOpen(true);
                }}
              >
                <Pencil data-icon="inline-start" />
                Edit
              </Button>
              <Button
                size="sm"
                variant="ghost"
                disabled={!wouldChange(true)}
                onClick={() => setEnforced(true)}
              >
                <ShieldCheck data-icon="inline-start" />
                Arm
              </Button>
              <Button
                size="sm"
                variant="ghost"
                disabled={!wouldChange(false)}
                onClick={() => setEnforced(false)}
              >
                <ShieldOff data-icon="inline-start" />
                Disarm
              </Button>
            </>
          }
        />

        <UnsavedChangesGuard when={dialogDirty} onNavigate={(href) => router.push(href)} />

        <TierDialog
          // Keyed by the TARGET, not by openness: reopening the same tier restores what was typed,
          // while pointing the dialog at another tier remounts it on that row's values.
          key={editingId ?? "none"}
          open={dialogOpen && editing !== null}
          tier={editing}
          onClose={() => setDialogOpen(false)}
          onDirtyChange={setDialogDirty}
        />

        <ProgressModal
          open={armRun.state.running || armRun.state.finished}
          title="Saving tiers"
          description="Each tier is saved on its own; a failure leaves the earlier saves in place."
          total={armRun.state.total}
          done={armRun.state.done}
          currentLabel={armRun.state.currentLabel}
          error={armRun.state.error}
          results={armRun.state.results}
          finished={armRun.state.finished}
          onContinue={armRun.continueRun}
          onStop={armRun.stop}
          onClose={() => {
            armRun.reset();
            list.clearSelection();
          }}
        />
      </div>
    </div>
  );
}

/**
 * One tier's nine editable values.
 *
 * Exported for its own unit tests — and because the page above is otherwise the only thing that
 * could exercise the blank-means-uncapped rule, which is exactly the rule most worth testing.
 *
 * Only the CHANGED fields are PUT. The endpoint is a patch, so sending all nine would write back
 * the seven the operator never touched, undoing whatever landed on them while the dialog sat open
 * — and on a table read by every metered request, that is a cap silently restored.
 */
export function TierDialog({
  open,
  tier,
  onClose,
  onDirtyChange,
}: {
  open: boolean;
  /** The row being edited, or `null` when the dialog is closed. There is no create mode. */
  tier: RateLimitTier | null;
  onClose: () => void;
  /** Reports whether the form holds unsaved input, so the page's guard covers it. */
  onDirtyChange: (dirty: boolean) => void;
}) {
  const updateTier = useUpdateRateLimitTier();
  const save = useAction();

  const initial = useMemo<TierDraft>(
    () =>
      tier
        ? draftFrom(tier)
        : {
            quotaEnforced: false,
            quotaRequests: "",
            quotaBytes: "",
            quotaTokens: "",
            quotaCostMicros: "",
            quotaPeriodDays: "",
            rateCapacity: "",
            rateRefillTokens: "",
            rateRefillSeconds: "",
          },
    [tier],
  );

  const [form, setForm] = useState<TierDraft>(initial);
  const formRef = useRef<HTMLFormElement>(null);
  // Focus when the input ATTACHES (dialog open) — the autoFocus prop is banned by
  // jsx-a11y/no-autofocus; a stable callback ref never re-steals focus on re-render.
  const focusOnAttach = useCallback((el: HTMLInputElement | null) => {
    el?.focus();
  }, []);

  const set = (field: NumericField, next: string) =>
    setForm((prev) => ({ ...prev, [field]: next }));

  const dirty = isTierFormDirty(form, initial);
  // Reported whether or not the dialog is OPEN. Closing keeps the draft (the page keys this
  // component by the target, not by openness), so a shut dialog holding unsaved input is exactly
  // the case the navigation guard exists for — gating on `open` would let the operator walk away
  // from typed values the moment they pressed Cancel, which is when they are most likely to.
  useEffect(() => onDirtyChange(dirty), [dirty, onDirtyChange]);
  const blockedReason = tierFormBlockedReason(form, initial);
  const canSave = dirty && blockedReason === null;

  function close() {
    if (save.busy) return;
    onClose();
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!tier) return;
    void save.run(async () => {
      // `bodyFrom` throws exactly what `blockedReason` reported (same source), so the sentence
      // beside the disabled Save is the one a click would have produced. useAction captures it.
      const changes = bodyFrom(tierChanges(form, initial));
      await updateTier.mutateAsync({ id: tier.id, changes });
      onClose();
    });
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && close()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Edit tier {tier?.slug ?? ""}</DialogTitle>
          <DialogDescription>
            Blank a quota to leave it uncapped. Caps only bite when this tier is armed AND the
            global switch is on.
          </DialogDescription>
        </DialogHeader>
        <form ref={formRef} onSubmit={handleSubmit} className="flex flex-col gap-4">
          <Label htmlFor="tier-dialog-enforced" className="font-normal">
            <Checkbox
              id="tier-dialog-enforced"
              checked={form.quotaEnforced}
              onCheckedChange={(checked) =>
                setForm((prev) => ({ ...prev, quotaEnforced: checked === true }))
              }
            />{" "}
            Enforced
          </Label>
          {/* Two columns: the four blankable period quotas, then the four required counts. The
              grouping is the gate's own — they parse by different rules and fail differently. */}
          <div className="grid grid-cols-2 gap-4">
            {NUMERIC_FIELDS.map((field, i) => {
              const spec = NUMERIC_SPEC[field];
              return (
                <Field key={field} label={spec.header} error={i === 0 ? save.error : undefined}>
                  <Input
                    value={form[field]}
                    onChange={(e) => set(field, e.target.value)}
                    placeholder={spec.placeholder}
                    title={spec.title}
                    inputMode="numeric"
                    className="text-right tabular-nums"
                    ref={i === 0 ? focusOnAttach : undefined}
                  />
                </Field>
              );
            })}
          </div>
          {/* Why Save is grey. An unedited tier is blocked by nothing, so this only ever appears
              once the operator has typed something the gate can't parse. Suppressed while
              `save.error` is showing so the two never argue. */}
          {!save.error && blockedReason && (
            <p className="text-sm text-apt-text-muted" role="status">
              {blockedReason}
            </p>
          )}
          {/* A submit button is what lets Enter submit a multi-input form; hidden because the
              visible confirm lives in DialogActions and calls form.requestSubmit(). It must carry
              the same disabled state as the visible confirm — being the form's implicit default
              button, Enter in any text field submits THIS button regardless of `hidden`; only
              `disabled` stops it. That includes `save.busy`: DialogActions drops the visible
              confirm while saving, leaving THIS the only reachable submit path. */}
          <button
            type="submit"
            className="hidden"
            aria-hidden
            tabIndex={-1}
            disabled={!canSave || save.busy}
          />
        </form>
        <DialogActions
          cancelLabel="Cancel"
          onCancel={close}
          confirmLabel="Save"
          onConfirm={() => formRef.current?.requestSubmit()}
          busy={save.busy}
          confirmDisabled={!canSave}
          focusOnMount={false}
        />
      </DialogContent>
    </Dialog>
  );
}

/**
 * The global switch. It writes the `usage_enforcement` row in `system.feature_flags` (the same
 * store the Feature Flags page edits), so there is no bespoke write endpoint behind it.
 *
 * The toggle always shows the STORED row, and the badge shows what is actually in force — those
 * differ exactly when a deploy-time `USAGE_ENFORCEMENT_ENABLED` is set, which wins in both
 * directions. Showing the effective value in the toggle instead would hide the value a later
 * un-setting of that variable will restore; disabling the toggle would strand the row at whatever
 * it happens to hold. So the control keeps editing what it controls, and the banner explains why a
 * click doesn't change the badge.
 */
function GlobalSwitchCard({ state }: { state: UsageEnforcement }) {
  const setEnforcement = useSetEnforcement();
  const save = useAction();
  const stored = state.flag?.enabled ?? false;

  return (
    <section className="mb-6 rounded-lg border border-apt-border bg-apt-surface p-4">
      <div className="flex flex-wrap items-center gap-3">
        <Switch
          checked={stored}
          onCheckedChange={(checked) =>
            void save.run(() =>
              setEnforcement.mutateAsync({ flagId: state.flag?.id ?? null, enabled: checked }),
            )
          }
          disabled={save.busy}
          aria-label="Enforce usage limits"
        />
        <span className="text-sm font-medium text-apt-text">Enforce usage limits</span>
        <Badge variant={state.enabled ? "orange" : "neutral"}>
          {state.enabled ? "enforcing" : "observe only"}
        </Badge>
      </div>

      <p className="mt-3 max-w-3xl text-sm text-apt-text-muted">
        {state.enabled
          ? "Armed: an armed tier now refuses over-cap traffic — 429 from its rate bucket, 402 once a period quota is exceeded."
          : "Off: usage is still recorded and counted, but no request is ever refused. Every tier’s Enforced box is inert."}
      </p>

      {state.envOverride !== null && (
        <Alert variant="accent" className="mt-4">
          <Info />
          <AlertTitle>The deployment environment is deciding this</AlertTitle>
          <AlertDescription>
            <span className="font-mono">USAGE_ENFORCEMENT_ENABLED</span> is set to{" "}
            <span className="font-mono">{String(state.envOverride)}</span>, and a deploy-time
            override wins over this row in both directions — the break-glass lever for when
            enforcement itself is what&apos;s refusing requests. The switch still edits the stored
            value (currently <strong>{stored ? "on" : "off"}</strong>), which takes effect the
            moment that variable is unset.
          </AlertDescription>
        </Alert>
      )}

      {state.flag === null && (
        <Alert variant="info" className="mt-4">
          <Info />
          <AlertTitle>No switch row yet</AlertTitle>
          <AlertDescription>
            The <span className="font-mono">usage_enforcement</span> feature flag doesn&apos;t
            exist, which reads as off. Flipping the switch creates it.
          </AlertDescription>
        </Alert>
      )}

      {save.error && (
        <Alert variant="error" className="mt-4">
          <TriangleAlert />
          <AlertTitle>Couldn&apos;t flip the switch</AlertTitle>
          <AlertDescription>{save.error}</AlertDescription>
        </Alert>
      )}
    </section>
  );
}

/** µUSD → a `$0.00` string. The API reports integer micro-dollars; nobody reads those. */
const dollars = (micros: number): string => `$${(micros / 1_000_000).toFixed(2)}`;

/**
 * The pricing and retention knobs, read-only: they come from the deployment environment, not from
 * any row, so the console can report them but not change them. They belong next to the switch
 * because they decide what enforcement charges the moment it bites.
 */
function KnobsPanel({ state }: { state: UsageEnforcement }) {
  const knobs: { label: string; value: string; env: string; note: string }[] = [
    {
      label: "Unpriced model",
      value: state.unknownPricePolicy,
      env: "USAGE_UNKNOWN_PRICE_POLICY",
      note:
        state.unknownPricePolicy === "ceiling"
          ? "charged at the worst-case ceiling below"
          : state.unknownPricePolicy === "refuse"
            ? "no published price, no turn"
            : "charged nothing — unbounded spend on unpriced models",
    },
    {
      label: "Ceiling — input",
      value: `${dollars(state.unknownPriceInputMicrosPerMToken)} / Mtok`,
      env: "USAGE_UNKNOWN_PRICE_INPUT_MICROS_PER_MTOKEN",
      note: `${state.unknownPriceInputMicrosPerMToken.toLocaleString()} µUSD per million tokens`,
    },
    {
      label: "Ceiling — output",
      value: `${dollars(state.unknownPriceOutputMicrosPerMToken)} / Mtok`,
      env: "USAGE_UNKNOWN_PRICE_OUTPUT_MICROS_PER_MTOKEN",
      note: `${state.unknownPriceOutputMicrosPerMToken.toLocaleString()} µUSD per million tokens`,
    },
    {
      label: "Turn reserve",
      value: `${state.turnTokenReserve.toLocaleString()} tokens`,
      env: "USAGE_TURN_TOKEN_RESERVE",
      note: "claimed up front per signed-in turn, settled to real spend when it ends",
    },
    {
      label: "Event retention",
      value: `${state.eventRetentionDays} days`,
      env: "USAGE_EVENT_RETENTION_DAYS",
      note: "age at which a usage_events row is swept; counters are kept forever",
    },
  ];

  return (
    <section className="mb-8 rounded-lg border border-apt-border p-4">
      <h2 className="text-sm font-semibold text-apt-text">Pricing &amp; retention</h2>
      <p className="mt-1 text-sm text-apt-text-muted">
        Set in the deployment environment — read-only here.
      </p>
      <dl className="mt-3 grid gap-x-6 gap-y-3 sm:grid-cols-2 lg:grid-cols-3">
        {knobs.map((knob) => (
          <div key={knob.env}>
            <dt className="text-xs uppercase tracking-wide text-apt-text-dim">{knob.label}</dt>
            <dd className="text-sm text-apt-text">
              <span className="font-mono">{knob.value}</span>
              <span className="block text-xs text-apt-text-muted">{knob.note}</span>
              <span className="block font-mono text-[0.65rem] text-apt-text-dim">{knob.env}</span>
            </dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

/**
 * The visitor floor's metered budgets — the ONLY caps on this page that refuse regardless of the
 * global switch above. They get their own section rather than three more rows in `KnobsPanel`
 * precisely because of that: an operator reading a page whose switch says "nothing is being
 * refused" would otherwise have to notice a per-row footnote to learn that anonymous chat is
 * still being cut off, and a caveat that important cannot live in a footnote.
 *
 * They are also the one place the unpriced-model ceiling turns into a number an operator can act
 * on. The reserve is claimed at the ceiling's OUTPUT rate, so with `ceiling` policy in force this
 * panel can say exactly how few unpriced turns exhaust a day's budget on money nobody was charged
 * — arithmetic that needs the reserve, the ceiling and the budget together, and so can only be
 * done here.
 */
function VisitorFloorPanel({ state }: { state: UsageEnforcement }) {
  const {
    visitorGlobalDailyTokenBudget: tokens,
    visitorGlobalDailyCostMicros: cost,
    visitorTurnTokenReserve: reserve,
    unknownPricePolicy: policy,
    unknownPriceOutputMicrosPerMToken: ceilingOut,
  } = state;

  // What one turn on an unpriced model claims, under today's policy. `free` charges nothing, so
  // the money budget cannot bite on guessed prices at all; `refuse` never gets as far as a claim.
  const reserveMicros = policy === "ceiling" ? Math.ceil((reserve * ceilingOut) / 1_000_000) : 0;
  const guessed =
    cost !== null && reserveMicros > 0
      ? { turns: Math.floor(cost / reserveMicros), budget: cost }
      : null;

  const knobs: { label: string; value: string; env: string; note: string }[] = [
    {
      label: "Daily tokens",
      value: tokens === null ? "lifted" : `${tokens.toLocaleString()} tokens`,
      env: "VISITOR_GLOBAL_DAILY_TOKEN_BUDGET",
      note:
        tokens === null
          ? "no token ceiling on anonymous chat — the money budget is the only backstop"
          : tokens === 0
            ? "zero — every anonymous turn is refused"
            : "LLM tokens per day, per owning ecosystem",
    },
    {
      label: "Daily spend",
      value: cost === null ? "lifted" : `${dollars(cost)} / day`,
      env: "VISITOR_GLOBAL_DAILY_COST_MICROS",
      note:
        cost === null
          ? "no spend ceiling on anonymous chat — the token budget is the only backstop"
          : cost === 0
            ? "zero — every anonymous turn is refused"
            : "provider spend per day, per owning ecosystem",
    },
    {
      label: "Turn reserve",
      value: `${reserve.toLocaleString()} tokens`,
      env: "VISITOR_TURN_TOKEN_RESERVE",
      note:
        reserveMicros > 0
          ? `claimed up front per anonymous turn — ${dollars(reserveMicros)} against the spend budget`
          : "claimed up front per anonymous turn, settled to real spend when it ends",
    },
  ];

  return (
    <section className="mb-8 rounded-lg border border-apt-border p-4">
      <h2 className="text-sm font-semibold text-apt-text">Visitor floor</h2>
      <p className="mt-1 text-sm text-apt-text-muted">
        Anonymous chat&apos;s own daily budgets. Unlike every tier on this page, these refuse{" "}
        <strong>whatever the switch above says</strong> — set one to{" "}
        <span className="font-mono">off</span> to lift it, or{" "}
        <span className="font-mono">0</span> to refuse every anonymous turn.
      </p>
      <dl className="mt-3 grid gap-x-6 gap-y-3 sm:grid-cols-2 lg:grid-cols-3">
        {knobs.map((knob) => (
          <div key={knob.env}>
            <dt className="text-xs uppercase tracking-wide text-apt-text-dim">{knob.label}</dt>
            <dd className="text-sm text-apt-text">
              <span className="font-mono">{knob.value}</span>
              <span className="block text-xs text-apt-text-muted">{knob.note}</span>
              <span className="block font-mono text-[0.65rem] text-apt-text-dim">{knob.env}</span>
            </dd>
          </div>
        ))}
      </dl>
      {guessed && (
        <Alert variant="accent" className="mt-4">
          <TriangleAlert className="h-4 w-4" />
          <AlertTitle>The spend budget can be exhausted by guessed money</AlertTitle>
          <AlertDescription>
            A model the catalog cannot price is charged the ceiling above, so{" "}
            {guessed.turns.toLocaleString()} concurrent anonymous turns on unpriced models hold the
            entire {dollars(guessed.budget)} budget — before anyone has spent a real cent. Publish
            prices for the models your personas use, or set{" "}
            <span className="font-mono">USAGE_UNKNOWN_PRICE_POLICY=refuse</span> so an unpriced
            model is turned away instead of charged a guess.
          </AlertDescription>
        </Alert>
      )}
    </section>
  );
}
