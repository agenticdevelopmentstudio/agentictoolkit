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

// Auth methods that connect real accounts (everything except ecosystem-only api_key), so a
// saved instance shows the connected-accounts manager below its cards.
//
// GITHUB_APP IS DELIBERATELY ABSENT, and its absence is the whole of that section's story here.
// The manager exists to let a person add and remove accounts — which for every method above is
// a real choice, made at the provider. A GitHub App has no such choice left: the account was
// picked on github.com at install time, and the app id and private key are enough for the
// backend to read the answer back. So the section had nothing to offer but a list the operator
// cannot act on, and every state it could show was a restatement of what the Test button below
// says about the same credentials. Adding "github_app" back here re-creates that duplicate.
const CONNECTION_METHODS: readonly ProviderAuthMethod[] = [
  "oauth",
  "oauth_instance",
  "plaid_link",
  "app_password",
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
 * Ask GitHub which accounts this app is installed on, and take the ones it can have.
 *
 * ONE CALL, TWO CALLERS, and the only difference between them is who is listening. It signs a JWT
 * with the saved app id and private key, lists the installations, and records each one — which is
 * what makes the repository picker open on a populated list instead of on an empty box.
 *
 * It is also, unavoidably, the credentials test: an installation list cannot be fetched without a
 * JWT GitHub accepts, so a wrong app id or an unimportable private key fails exactly here.
 */
async function adoptInstallations(
  providerId: string,
  ecosystemId: string,
  providerConfigId: string,
): Promise<string> {
  const { connected, skipped } = await integrationsApi.adoptInstallations(providerId, {
    ecosystemId,
    providerConfigId,
  });
  const name = (r: { accountLogin: string; installationId: string }) =>
    r.accountLogin || `installation ${r.installationId}`;
  // A skip carrying a connectionId is one this ecosystem ALREADY holds — re-testing a working
  // integration is a no-op, not a failure. One without is a refusal, and has to be voiced.
  const held = skipped.filter((s) => s.connectionId);
  const blocked = skipped.filter((s) => !s.connectionId);
  const said: string[] = [];
  if (connected.length > 0) said.push(`Connected ${connected.map(name).join(", ")}.`);
  if (held.length > 0) said.push(`${held.map(name).join(", ")} was already connected.`);
  for (const b of blocked) said.push(`${name(b)}: ${b.skipped}`);
  // A `warning` is NOT a skip and is never counted as one — the connection stands, and only
  // the repository download behind it did not finish. It is said out loud anyway, because
  // this is the Test button: the next thing that happens is somebody opening a picker, and
  // finding out there why it is empty is finding out too late. It rides on a connected row
  // or on a held one, so both are read for it.
  for (const w of [...connected, ...held]) {
    if (w.warning) said.push(`${name(w)} is connected, but its repository list could not be downloaded: ${w.warning}`);
  }
  if (said.length > 0) return said.join(" ");
  // Credentials GitHub accepted, and nothing installed anywhere. A true answer with its own fix,
  // so it is a result rather than an error.
  return (
    "These credentials work, but the app isn't installed on any account yet. Install it on " +
    "GitHub — on your own account or an organization — then test again."
  );
}

/**
 * The same call, fired by a SAVE, with nobody listening.
 *
 * Saving saves. It does not test, it does not report, and it does not wait — but the moment a
 * GitHub App's credentials land there is exactly one useful thing to do with them, and doing it
 * now is the difference between a repository picker that opens full and one that opens empty. So
 * the download rides along and its outcome goes nowhere: it worked, and the lists are already
 * there when someone asks for them; it did not, and they find out when they press Test, or when
 * the picker tells them why it has nothing to show.
 *
 * NOT AWAITED, and that is the point — a save that blocked on a round-trip to github.com would be
 * a test with the reporting removed, which is the worse half of both.
 */
function prefetchInstallations(
  provider: ProviderCatalogEntry,
  ecosystemId: string,
  providerConfigId: string,
): void {
  if (provider.authMethod !== "github_app") return;
  void adoptInstallations(provider.providerId, ecosystemId, providerConfigId).catch(() => {
    // Deliberately empty. Test is where this question gets asked out loud.
  });
}

/** The Test half — the same download as the save's, with its mouth open. */
export interface IntegrationTest {
  /** Whether there is anything here to test. */
  available: boolean;
  /** Why the button is disabled, or null. */
  blockedReason: string | null;
  /** Never throws — a failure lands on `error`. */
  run: () => Promise<void>;
  busy: boolean;
  /** What GitHub answered, when it answered. */
  result: string | null;
  error: string | null;
}

/**
 * Reach the provider with the credentials as they are STORED, and say what came back.
 *
 * Separate from `useIntegrationSubmit` because it is a separate responsibility: that one writes
 * fields, this one asks a question of a third party. One button doing both would mean neither
 * could be done alone — no way to re-read the installations after installing the app on a second
 * organization without re-saving a form nothing had changed in, and no way to save a half-typed
 * key without being told off by github.com.
 *
 * It tests what is SAVED, not what is typed, which is why an edited form disables it: testing a
 * key the backend has never seen would report on credentials that do not exist, and nothing on
 * screen would say which of the two the answer was about.
 */
export function useIntegrationTest({
  provider,
  ecosystemId,
  config,
  dirty,
}: {
  provider: ProviderCatalogEntry;
  ecosystemId: string;
  config: MaskedProviderConfig | null;
  dirty: boolean;
}): IntegrationTest {
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const configId = config?.id ?? null;

  const run = async () => {
    if (!configId || busy) return;
    setBusy(true);
    setResult(null);
    setError(null);
    try {
      setResult(await adoptInstallations(provider.providerId, ecosystemId, configId));
    } catch (e) {
      setError(errMsg(e, "GitHub could not be reached with these credentials."));
    } finally {
      setBusy(false);
    }
  };

  return {
    available: provider.authMethod === "github_app" && configId !== null,
    blockedReason: dirty ? "Save your changes before testing them." : null,
    run,
    busy,
    result,
    error,
  };
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
  /** Different from what is stored — false in `'add'` mode, which has no stored anything. */
  dirty: boolean;
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

  const run = async () => {
    // The guard is HERE and not only on the button, because Enter reaches this through a form
    // submit as well now — and a keystroke must not be able to post a draft a click could not.
    if (!canSubmit || busy) return;
    setBusy(true);
    setError(null);
    try {
      if (mode === "add") {
        setAdded(false);
        const row = await integrationsApi.createProviderConfig(
          ecosystemId,
          intToCreateBody(draft, provider),
        );
        prefetchInstallations(provider, ecosystemId, row.id);
        setAdded(true);
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
        prefetchInstallations(provider, ecosystemId, row.id);
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
    dirty: mode === "saved" && dirty,
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
  // Not lifted the way `submit` is, because Test has no second home: the Add dialog's footer
  // draws OK and Cancel, and a button that reaches credentials the operator has not saved yet
  // would have nothing to reach. It lives beside Save, in the card that owns the fields it tests.
  const test = useIntegrationTest({
    provider,
    ecosystemId,
    config: config ?? null,
    dirty: submit.dirty,
  });
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
            {(!hideSubmit || test.available) && (
              <div className="flex flex-wrap items-center gap-2">
                {!hideSubmit && (
                  <Button
                    type="button"
                    variant="default"
                    disabled={!submit.canSubmit || submit.busy}
                    onClick={() => void submit.run()}
                  >
                    {submit.busy ? submit.busyLabel : submit.label}
                  </Button>
                )}
                {/* Save writes the fields; Test asks GitHub about them. Two buttons because they
                    are two questions, and an operator who has installed the app on a new
                    organization needs to ask the second one without re-answering the first. */}
                {test.available && (
                  <Button
                    type="button"
                    variant="secondary"
                    disabled={test.busy || test.blockedReason !== null}
                    onClick={() => void test.run()}
                  >
                    {test.busy ? "Testing…" : "Test"}
                  </Button>
                )}
              </div>
            )}
            {!hideSubmit && submit.added && (
              <p className="text-sm text-apt-green">integration added</p>
            )}
            <ErrorText error={submit.error} />
            {/* The test's own answer, kept separate from the save's: they are replies to two
                different questions, and merging them is what made a save look like it had
                reached GitHub when it had not. */}
            <ErrorText error={test.error} />
            {test.result && !test.error && (
              <p className="text-sm text-apt-text" role="status">
                {test.result}
              </p>
            )}
            {test.available && test.blockedReason && (
              <p className="text-sm text-apt-text-muted" role="status">
                {test.blockedReason}
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
