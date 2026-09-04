"use client";

import { useState } from "react";
import { Card, CardHeader, CardTitle, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { CopyButton } from "@agenticdevelopertoolkit/ui/components/copy-button";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import {
  integrationsApi,
  type DeliverabilityWebhook,
  type MaskedProviderConfig,
  type ProviderAuthMethod,
  type ProviderCatalogEntry,
} from "@agentic-toolkit/data/integrations";
import { errMsg } from "@agentic-toolkit/data";
import {
  ApiKeyFields,
  NonConfigurableNote,
  OAuthFields,
  hasConfigFields,
  intBlank,
  intDiffers,
  intToBody,
  intToCreateBody,
  intToInput,
  intValidate,
  ownerConfigurable,
  type IntegrationInput,
} from "./IntegrationDetail";
import { ProviderConnections } from "./ProviderConnections";
import { IntegrationData, providerDataTables } from "./IntegrationData";
import { DetailSection } from "@agentic-toolkit/resource";

/**
 * The shared 3-card provider view — one component behind both the Add-integration
 * modal (`mode='add'`, D2) and the saved-instance detail (`mode='saved'`, E1). Card 1
 * is provider info, Card 2 is the Name field + auth-method config + the create/save
 * button, and Card 3 is a plain-language capability summary. Saved OAuth-family
 * instances also surface `ProviderConnections` below the cards.
 */
export type IntegrationDetailViewProps = {
  provider: ProviderCatalogEntry;
  ecosystemId: string;
  /** 'add' = create button; 'saved' = save button + connected-accounts section. */
  mode: "add" | "saved";
  /** Present in 'saved' mode: the existing instance (null while adding). */
  config?: MaskedProviderConfig | null;
  /** Draft state (lifted so the Add modal can persist it). `name` is part of the draft. */
  draft: IntegrationInput;
  onChange: (next: IntegrationInput) => void;
  /** Called after a successful create ('add') or save ('saved') with the masked row. */
  onSaved?: (row: MaskedProviderConfig) => void;
  /**
   * Called after a webhook-secret rotation with the updated masked row. Separate from `onSaved`
   * on purpose: rotating a secret writes ONE server-managed field and touches nothing the
   * operator has typed, so re-deriving the draft from the response (which `onSaved` does, to
   * clear the just-typed secret) would silently discard unsaved edits to the config fields.
   */
  onRotated?: (row: MaskedProviderConfig) => void;
};

/** The one save-blocking rule `intValidate` doesn't cover (it validates provider fields, not the
 *  instance label). Same wording as the toolkit service editor's, so the platform says one thing. */
const NAME_REQUIRED_MESSAGE = "A name is required.";

// Auth methods that connect real accounts (everything except ecosystem-only api_key),
// so a saved instance shows the connected-accounts manager below its cards. github_app is
// here for the same reason as oauth: one installation of the app is one connected account.
const CONNECTION_METHODS: readonly ProviderAuthMethod[] = [
  "oauth",
  "oauth_instance",
  "plaid_link",
  "app_password",
  "github_app",
];

/** A one-sentence, plain-language summary of what enabling this provider does. */
function describeCapabilities(provider: ProviderCatalogEntry): string {
  const name = provider.displayName;
  const parts: string[] = [];
  for (const cap of provider.capabilities) {
    if (cap === "read") parts.push(`Syncs data from ${name} into your ecosystem.`);
    else if (cap === "write") parts.push(`Lets your ecosystem post or send through ${name}.`);
    else if (cap === "auth") parts.push(`Registers ${name} for account connections.`);
  }
  if (parts.length === 0) return `Connects ${name} to your ecosystem.`;
  return parts.join(" ");
}

/**
 * The deliverability webhook an operator has to register with the provider (Postmark today).
 *
 * This is the ONLY place the URL and its secret are ever shown. Until the webhook is registered
 * the provider never reports a bounce — which leaves `delivery_status` a column nothing writes
 * and every suppression filter reading a dead value. That failure is completely silent from the
 * operator's side (mail keeps "sending"), so the block states the consequence rather than just
 * offering a URL.
 *
 * The secret is THIS ECOSYSTEM's own, not a deployment-wide value: it is what makes an inbound
 * webhook prove which tenant it speaks for. So it is rendered here beside the URL — the two are
 * useless apart — with a rotate action for compromise response and for the configs created
 * before per-config secrets existed, which arrive with `secret: null` and cannot authenticate
 * anything until one is minted.
 *
 * Neither `null` case is rendered as nothing. A missing webhook (`webhook === null`) means the
 * deployment has no public base URL, so there is no address to hand out; a missing secret means
 * the URL exists but every call to it is refused. Both are operator-visible facts, and silence
 * there is indistinguishable from "already handled".
 */
function DeliverabilityWebhookCard({
  webhook,
  ecosystemId,
  configId,
  onRotated,
}: {
  webhook: DeliverabilityWebhook | null;
  ecosystemId: string;
  configId: string;
  onRotated?: (row: MaskedProviderConfig) => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // A secret already in place makes this DESTRUCTIVE (the old one stops working the instant it
  // returns); with none stored it is the only way to get a working webhook at all. Same action,
  // two very different warnings — so the label and the confirmation both follow the state.
  const hasSecret = webhook?.secret != null;

  const doRotate = async () => {
    if (
      !confirm(
        hasSecret
          ? "Generate a new webhook secret? The current one stops working immediately, so " +
              "the provider will reject every event — no bounce or complaint will be recorded — " +
              "until you paste the new secret into its webhook settings."
          : "Generate a webhook secret for this integration? You will need to paste it into " +
              "the provider's webhook settings before any bounce or complaint is recorded.",
      )
    ) {
      return;
    }
    setBusy(true);
    setError(null);
    try {
      // Rotate FIRST, then notify. `onRotated?.(await rotate(...))` reads the same but is not:
      // optional-call short-circuits its own ARGUMENTS, so with no listener attached the request
      // would never be sent and the button would do nothing at all.
      const row = await integrationsApi.rotateWebhookSecret(ecosystemId, configId);
      onRotated?.(row);
    } catch (e) {
      setError(errMsg(e, "Couldn't generate a new webhook secret."));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Deliverability webhook</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {webhook === null ? (
          <p className="text-sm text-apt-red">
            This deployment has no public base URL configured, so there is no address to register
            yet. Until an administrator sets one, bounced and complained addresses are never
            suppressed and will be mailed again. (Set <code>AUDIENCE_PUBLIC_BASE_URL</code> on the
            backend.)
          </p>
        ) : (
          <>
            {/* The instruction comes from the backend, alongside the URL, so the copy naming the
                provider's own setting cannot drift away from the route that actually accepts it. */}
            <p className="text-sm text-apt-text-muted">{webhook.instruction}</p>
            <div className="flex items-center gap-2">
              <code className="min-w-0 flex-1 overflow-x-auto rounded-md border border-apt-border bg-apt-surface-2 p-2 text-xs text-apt-text">
                {webhook.url}
              </code>
              <CopyButton label="Copy webhook URL" getText={() => webhook.url} />
            </div>

            <p className="text-xs text-apt-text-muted">
              Send this secret in the <code>{webhook.secretHeader}</code> header. It belongs to
              this ecosystem alone — an event that does not carry it is rejected.
            </p>
            {webhook.secret === null ? (
              <p className="text-sm text-apt-red">
                No secret is stored for this integration, so every event sent to the URL above is
                rejected and no bounce or complaint is being recorded. Generate one below, then
                paste it into the provider.
              </p>
            ) : (
              <div className="flex items-center gap-2">
                <code className="min-w-0 flex-1 overflow-x-auto rounded-md border border-apt-border bg-apt-surface-2 p-2 text-xs text-apt-text">
                  {webhook.secret}
                </code>
                <CopyButton label="Copy webhook secret" getText={() => webhook.secret ?? ""} />
              </div>
            )}

            <div className="flex items-center gap-3">
              {/* Same confirm() idiom as the list embed-key rotation and AccessTokensSection's
                  revoke — the established destructive-action pattern here, not a bespoke modal. */}
              <Button
                type="button"
                variant={hasSecret ? "destructive-ghost" : "default"}
                size="sm"
                disabled={busy}
                onClick={() => void doRotate()}
              >
                {busy
                  ? "Generating…"
                  : hasSecret
                    ? "Generate a new secret"
                    : "Generate a secret"}
              </Button>
            </div>
            {/* `ErrorText`, not this file's local raw-`<p>` idiom: this is the one error here
                that appears LATE, in response to a click, so a screen reader has already read
                past this point in the document and will never encounter it without the
                `role="alert"` the shared component carries. (The two static warnings above are
                present from first paint and are read in normal document order, which is why
                they are left as they were.) */}
            <ErrorText error={error} />
          </>
        )}
      </CardContent>
    </Card>
  );
}

/** Picks the extracted field block for the provider's auth method (mirrors the legacy
 *  `IntegrationDetail` branching). The blocks read `config.hasSecret` themselves to show
 *  the "leave blank to keep" secret placeholder, so no extra mode wiring is needed. */
function FieldsForMethod({
  provider,
  draft,
  onChange,
  config,
}: {
  provider: ProviderCatalogEntry;
  draft: IntegrationInput;
  onChange: (next: IntegrationInput) => void;
  config: MaskedProviderConfig | null;
}) {
  const props = { provider, draft, onChange, config };
  // configFields FIRST (api_key + bluesky/mastodon), so an OAuth-family authMethod with a
  // declared config spec still gets ApiKeyFields — see hasConfigFields in IntegrationDetail.
  if (hasConfigFields(provider)) return <ApiKeyFields {...props} />;
  if (!ownerConfigurable(provider.authMethod)) return <NonConfigurableNote {...props} />;
  return <OAuthFields {...props} />;
}


/**
 * THE CREATE/SAVE HALF, hoisted out of the component that draws it.
 *
 * A hook rather than a method on the view, because the button does not always live inside the
 * view. The Add flow puts it in a dialog FOOTER — under the scroll region, beside Cancel, where
 * a form's OK button belongs and where Enter can reach it — and a button rendered in one subtree
 * cannot be moved into another. Lifting the state is what keeps exactly one copy of "is this
 * draft submittable, and what happens when it is", wherever it happens to be drawn.
 */
export interface IntegrationSubmit {
  /** Create (`mode: 'add'`) or update (`'saved'`). Never throws — a failure lands on `error`. */
  run: () => Promise<void>;
  busy: boolean;
  /** A create succeeded and the form was cleared so another instance can be added. */
  added: boolean;
  error: string | null;
  /** Valid, and — in `'saved'` mode — actually different from what is stored. */
  canSubmit: boolean;
  /** Why it cannot be submitted, or null. A REASON rather than a bare boolean, because the gate
   *  disables the button and a disabled button that will not say why is the whole problem. */
  blockedReason: string | null;
  /** Whether the operator has typed enough for `blockedReason` to be worth voicing. */
  touched: boolean;
  /**
   * What the save ALSO did, when saving does more than store fields — today, the GitHub App
   * auto-connect's account list. Not an error and not a substitute for one: `error` says the
   * save or the connect failed, `notice` says what succeeded.
   */
  notice: string | null;
  /** What the button says, idle and mid-flight. */
  label: string;
  busyLabel: string;
}

export function useIntegrationSubmit({
  provider,
  ecosystemId,
  mode,
  config = null,
  draft,
  onChange,
  onSaved,
}: {
  provider: ProviderCatalogEntry;
  ecosystemId: string;
  mode: "add" | "saved";
  config?: MaskedProviderConfig | null;
  draft: IntegrationInput;
  onChange: (next: IntegrationInput) => void;
  onSaved?: (row: MaskedProviderConfig) => void;
}): IntegrationSubmit {
  const [busy, setBusy] = useState(false);
  const [added, setAdded] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  // A row a previous attempt CREATED and then failed to connect. Held so pressing OK again
  // corrects that row instead of adding a second one: an operator who pastes a private key
  // GitHub refuses, fixes it, and submits again must not end up with two integrations, one of
  // which never worked. Cleared the moment a save completes end to end.
  const [created, setCreated] = useState<MaskedProviderConfig | null>(null);
  // The loaded baseline for a 'saved' instance, captured once (this component is remounted
  // per row via `key={cfg.rdid}` in IntegrationsPane) and re-set after our own successful save
  // — so Save stays enabled the instant something changes but goes back to disabled right after
  // persisting, without waiting on the pane's separate (async) config refetch to catch up.
  // 'add' has no baseline; it's a genuine create-only view (see canSubmit below).
  const [baseline, setBaseline] = useState<IntegrationInput | null>(() =>
    mode === "saved" && config ? intToInput(config, provider) : null,
  );

  // `intValidate` already returns the exact sentence for a missing spec field or Client ID; the
  // name rule gets the same wording the toolkit's service editor uses. Name first: it is the
  // first field on the card.
  const blockedReason =
    draft.name.trim() === "" ? NAME_REQUIRED_MESSAGE : intValidate(draft, provider, config ?? null);
  // 'add' has no baseline to diff against — any valid draft is submittable. 'saved' also
  // requires an actual change vs. the loaded instance (name-inclusive: unlike the pane-exit
  // guard, a name-only edit should still enable this view's own Save button).
  const dirty =
    mode === "add" || baseline === null || intDiffers(draft, baseline, { includeName: true });
  // `busy` is deliberately NOT folded in (that belongs at the button, per useDirtyDraft's note):
  // canSubmit is a statement about the DRAFT, so the reason below can key off the same term.
  const canSubmit = dirty && blockedReason === null;
  // Whether to VOICE the reason. 'add' hard-codes `dirty` true, so it can't double as "the user
  // has given us something to complain about" — an empty Add form must not open by scolding.
  const touched =
    mode === "add" ? intDiffers(draft, intBlank(provider.providerId), { includeName: true }) : dirty;

  /**
   * CONNECTING IS PART OF SAVING, for a GitHub App.
   *
   * Every other auth method redirects to the provider because a PERSON has to choose an account
   * there. A GitHub App has no such question left: the choice was made on github.com when the
   * app was installed, and the backend can read the answer from the app id and private key
   * alone. So there is no "Connect account" step to take — the save takes it.
   *
   * It is also the credentials TEST. The only way to list installations is to sign a JWT GitHub
   * accepts, so a wrong app id or a key that will not import fails HERE, while the operator is
   * still looking at the fields they typed, instead of silently at the first sync.
   *
   * `ok` is false when nothing ended up connected — valid credentials for an app installed
   * nowhere. Throws with the provider's own words when the credentials themselves are refused.
   */
  const autoConnect = async (
    row: MaskedProviderConfig,
  ): Promise<{ ok: boolean; message: string }> => {
    const { connected, skipped } = await integrationsApi.adoptInstallations(provider.providerId, {
      ecosystemId,
      providerConfigId: row.id,
    });
    const name = (r: { accountLogin: string; installationId: string }) =>
      r.accountLogin || `installation ${r.installationId}`;
    // A skip carrying a connectionId is one THIS ecosystem already holds — re-saving a working
    // integration is a no-op, not a failure. One without is a refusal that has to be voiced.
    const held = skipped.filter((s) => s.connectionId);
    const blocked = skipped.filter((s) => !s.connectionId);
    const parts: string[] = [];
    if (connected.length > 0) parts.push(`Connected ${connected.map(name).join(", ")}.`);
    if (held.length > 0) parts.push(`${held.map(name).join(", ")} was already connected.`);
    for (const b of blocked) parts.push(`${name(b)}: ${b.skipped}`);
    if (connected.length + held.length === 0) {
      return {
        ok: false,
        message:
          parts.join(" ") ||
          "These credentials work, but the app isn't installed on any account yet. Install it " +
            "on GitHub — on your own account or an organization — then press OK again.",
      };
    }
    return { ok: true, message: parts.join(" ") };
  };

  const run = async () => {
    // The guard is HERE and not only on the button, because Enter reaches this through a form
    // submit as well now — and a keystroke must not be able to post a draft a click could not.
    if (!canSubmit || busy) return;
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      if (mode === "add") {
        setAdded(false);
        // `created` is non-null only after an attempt that saved the row and then could not
        // connect it, so this is the CORRECTION path, not a second integration.
        const row = created
          ? await integrationsApi.updateProviderConfig(ecosystemId, created.id, {
              name: draft.name.trim(),
              ...intToBody(draft, provider),
            })
          : await integrationsApi.createProviderConfig(
              ecosystemId,
              intToCreateBody(draft, provider),
            );
        setCreated(row);
        if (provider.authMethod === "github_app") {
          let outcome: { ok: boolean; message: string };
          try {
            outcome = await autoConnect(row);
          } catch (e) {
            // The integration IS saved — it is the credentials inside it GitHub refused. Say
            // both: "couldn't add the integration" would send the operator hunting for a row
            // that is already there, and hide the one sentence that says what to fix.
            setError(
              `Saved, but GitHub refused these credentials: ${errMsg(
                e,
                "the installations could not be read.",
              )}`,
            );
            return;
          }
          setNotice(outcome.message);
          // Nothing connected. The row is saved and its credentials are good, so this is not an
          // error — but closing now would land the operator on an empty connections list with
          // no explanation, which is the exact dead end this whole path exists to remove.
          if (!outcome.ok) return;
        }
        setAdded(true);
        setCreated(null);
        // Clear the form but stay open so another instance can be added.
        onChange({ ...intBlank(provider.providerId), name: "" });
        onSaved?.(row);
      } else {
        if (!config) return;
        const row = await integrationsApi.updateProviderConfig(ecosystemId, config.id, {
          name: draft.name.trim(),
          ...intToBody(draft, provider),
        });
        setBaseline(intToInput(row, provider));
        // Re-saving a GitHub App re-runs the connect, which is what makes a corrected key take
        // effect without a second UI. Already-held installations come back as skips, so this is
        // idempotent; a failure here is reported without pretending the save failed too.
        if (provider.authMethod === "github_app") {
          try {
            setNotice((await autoConnect(row)).message);
          } catch (e) {
            setError(
              `Saved, but GitHub refused these credentials: ${errMsg(
                e,
                "the installations could not be read.",
              )}`,
            );
            return;
          }
        }
        onSaved?.(row);
      }
    } catch (e) {
      setError(
        errMsg(
          e,
          mode === "add" ? "Couldn't add the integration." : "Couldn't save the integration.",
        ),
      );
    } finally {
      setBusy(false);
    }
  };

  return {
    run,
    busy,
    added,
    error,
    notice,
    canSubmit,
    blockedReason,
    touched,
    label: mode === "add" ? "Add Integration" : "Save",
    busyLabel: mode === "add" ? "Adding…" : "Saving…",
  };
}

export type IntegrationDetailBodyProps = Omit<IntegrationDetailViewProps, "onSaved"> & {
  /** The lifted submit state — `useIntegrationSubmit`'s return. */
  submit: IntegrationSubmit;
  /**
   * The HOST is drawing the submit button, so this body must not draw a second one.
   *
   * Set by the per-provider Add dialog, whose OK lives in its footer. The error line and the
   * blocked-reason line stay here either way: both are about the FIELDS, and an explanation of
   * why a button is grey belongs beside the field that greyed it, not orphaned under a footer
   * two scroll regions away.
   */
  hideSubmit?: boolean;
};

/** The cards, with no opinion about where the submit button goes. */
export function IntegrationDetailBody({
  provider,
  ecosystemId,
  mode,
  config,
  draft,
  onChange,
  onRotated,
  submit,
  hideSubmit = false,
}: IntegrationDetailBodyProps) {
  const showConnections = mode === "saved" && CONNECTION_METHODS.includes(provider.authMethod);
  // Synced-row browsing (reddit / google-calendar today) belongs to a SAVED instance — there is
  // nothing to browse while adding one. Empty for every other provider, which renders no section.
  const showData = mode === "saved" && providerDataTables(provider.providerId).length > 0;
  // Keyed off the field's PRESENCE, not off a `providerId === 'postmark'` test: the backend is the
  // one that decides which providers feed suppression, and re-deciding that here would silently
  // hide the block the day a second provider starts sending the field. `undefined` (this provider
  // has no webhook, and the whole `mode === 'add'` case, where there is no saved config at all)
  // renders nothing; `null` (no secret configured) renders the warning above.
  const webhook = config?.deliverabilityWebhook;

  return (
    <div className="flex flex-col gap-6">
      {/* Card 1 — provider info. NOT drawn when the host is drawing the submit button, because
          that host is the per-provider Add dialog: its title bar already carries the provider's
          name and its description line already carries this copy, and repeating both an inch
          lower is how a dialog that should be four fields tall becomes a page. */}
      {!hideSubmit && (
        <Card>
          <CardHeader>
            <CardTitle>{provider.displayName}</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-3">
            {provider.subtitle && (
              <p className="text-xs uppercase tracking-wide text-apt-text-dim">
                {provider.subtitle}
              </p>
            )}
            {provider.description && <p className="text-sm text-apt-text">{provider.description}</p>}
            {provider.links.length > 0 && (
              <div className="flex flex-wrap gap-3">
                {provider.links.map((l) => (
                  <a
                    key={l.url}
                    href={l.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-sm text-apt-gold hover:underline"
                  >
                    {l.label} ↗
                  </a>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Card 2 — config: name + auth fields + create/save */}
      <Card>
        <CardHeader>
          <CardTitle>Configuration</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-5">
          <div className="flex flex-col gap-2">
            <Label htmlFor="int-name">Name</Label>
            <Input
              id="int-name"
              value={draft.name}
              placeholder={provider.displayName}
              onChange={(e) => onChange({ ...draft, name: e.target.value })}
            />
            <p className="text-xs text-apt-text-muted">
              A label for this integration. You can rename it later.
            </p>
          </div>

          <FieldsForMethod
            provider={provider}
            draft={draft}
            onChange={onChange}
            config={config ?? null}
          />

          <div className="flex flex-col gap-2">
            {!hideSubmit && (
              <div>
                <Button
                  type="button"
                  variant="default"
                  disabled={!submit.canSubmit || submit.busy}
                  onClick={() => void submit.run()}
                >
                  {submit.busy ? submit.busyLabel : submit.label}
                </Button>
              </div>
            )}
            {!hideSubmit && submit.added && (
              <p className="text-sm text-apt-green">integration added</p>
            )}
            <ErrorText error={submit.error} />
            {/* Ungated by `hideSubmit` for the same reason the error line is: this is the
                outcome of the save, and the Add dialog — which draws its own OK in a footer two
                scroll regions away — is exactly where it must not go missing. */}
            {submit.notice && !submit.error && (
              <p className="text-sm text-apt-text" role="status">
                {submit.notice}
              </p>
            )}
            {!submit.error && submit.blockedReason && submit.touched && (
              <p className="text-sm text-apt-text-muted" role="status">
                {submit.blockedReason}
              </p>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Deliverability webhook — directly under Configuration, because registering it is the
          other half of setting the provider up, and an operator who scrolls past it gets silent
          suppression failures. */}
      {webhook !== undefined && config && (
        <DeliverabilityWebhookCard
          webhook={webhook}
          ecosystemId={ecosystemId}
          configId={config.id}
          // The host has to be told, not just the card: IntegrationsPane renders this view from
          // `selectedInList ?? fetchedCfg`, so without a refresh the cached list row keeps showing
          // the RETIRED secret — the one value an operator must not copy.
          onRotated={onRotated}
        />
      )}

      {/* Card 3 — what this does. Suppressed alongside Card 1 for the Add dialog: the picker the
          operator just came through said what each service does, in its own words, and a dialog
          that re-answers a question already answered is a dialog they have to scroll past. */}
      {!hideSubmit && (
        <Card>
          <CardHeader>
            <CardTitle>What this does</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-apt-text-muted">{describeCapabilities(provider)}</p>
          </CardContent>
        </Card>
      )}

      {showConnections && (
        <ProviderConnections
          provider={provider}
          ecosystemId={ecosystemId}
          providerConfig={config ?? null}
        />
      )}

      {/* Synced data — the generic table views over this provider's rows in the VIEWED
          ecosystem. Pre-rework this was a "Data" topic beside "Configuration"; the detail is
          now one scrolling column, so it renders as the last section (a provider with several
          browsable tables still publishes its own rail level from inside IntegrationData). */}
      {showData && (
        <DetailSection title="Synced data">
          <IntegrationData providerId={provider.providerId} ecosystemId={ecosystemId} />
        </DetailSection>
      )}
    </div>
  );
}

/** The self-contained view: owns its own submit and draws its own button. This is what the
 *  saved-instance detail mounts; the Add dialog composes the hook and the body itself, so that
 *  its OK can sit in the footer where Enter and Escape can reach it. */
export function IntegrationDetailView(props: IntegrationDetailViewProps) {
  const submit = useIntegrationSubmit(props);
  return <IntegrationDetailBody {...props} submit={submit} />;
}
