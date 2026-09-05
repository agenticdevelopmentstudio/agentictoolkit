"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  integrationsApi,
  oauthCallbackUrl,
  type MaskedProviderConfig,
  type ProviderCatalogEntry,
} from "@agentic-toolkit/data/integrations";
import { currentReturnTo, stashPendingConnect } from "./oauth-callback-store";
import { PlaidLinkLauncher } from "./PlaidLinkLauncher";
import { errMsg } from "@agentic-toolkit/data";

/**
 * The "Connect account" dialog — branches on the provider's catalog `authMethod`:
 *   • api_key       → the provider's spec-driven configFields → connect
 *   • app_password  → connect the saved config's handle + app-password (no inline entry)
 *   • oauth         → getAuthUrl → stash context → browser redirect (finished on the callback route)
 *   • oauth_instance→ registerInstance from the saved config → stash context → redirect to authorizeUrl
 *   • plaid_link    → mints a link token, opens Plaid Link (PlaidLinkLauncher), then
 *                     exchanges the returned public_token via connect.
 *
 * Direct (non-redirect) methods finish in place and call `onConnected` to refresh.
 * Redirect methods hand off to `app/integrations/oauth-callback`.
 *
 * `github_app` IS NOT HERE, and its absence is the design. Every method above exists because a
 * person has to answer something at the provider — which account, which credentials. A GitHub
 * App has already been answered: the account was chosen on github.com at install time, and the
 * backend reads it back from the saved app id and private key. So it connects at SAVE time
 * (`useIntegrationSubmit`'s silent prefetch) and on demand from the Test button beside it
 * (`useIntegrationTest`), and never opens a dialog. Adding a `github_app` case back here would
 * restore the "Connect account → Continue to GitHub" detour those two paths exist to remove.
 */
export function ConnectAccountDialog({
  provider,
  ecosystemId,
  providerConfig,
  open,
  onOpenChange,
  onConnected,
}: {
  provider: ProviderCatalogEntry;
  ecosystemId: string;
  /** The saved ecosystem provider-config instance for this provider (null while none is
   *  saved). A real-account connect SOURCES its creds from it — the resulting connection
   *  links it via provider_config_id — so connecting is gated on it existing. */
  providerConfig: MaskedProviderConfig | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onConnected: () => void;
}) {
  const { authMethod, providerId, displayName } = provider;
  const serviceType = provider.serviceTypes[0] ?? "";
  // api_key providers render their declared configFields (same spec as the ecosystem editor).
  const specFields = provider.configFields ?? [];
  // Every real-account connect (app_password / oauth / oauth_instance / plaid_link) sources its
  // creds from the saved config, so connecting is blocked until one exists.
  const providerConfigId = providerConfig?.id;
  const needsConfig =
    authMethod === "app_password" ||
    authMethod === "oauth" ||
    authMethod === "oauth_instance" ||
    authMethod === "plaid_link";
  const blocked = needsConfig && providerConfigId == null;
  // Non-secret fields read off the saved config for display + register-schema compliance.
  const configIdentifier = String(providerConfig?.config.identifier ?? "").trim();
  const configInstanceUrl = String(providerConfig?.config.instanceUrl ?? "").trim();

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Field state (only the relevant subset is used per method).
  const [fields, setFields] = useState<Record<string, string>>({});
  // Mounting the launcher with a token IS the "Plaid Link is open" state.
  const [plaidLinkToken, setPlaidLinkToken] = useState<string | null>(null);

  // Guards setState after unmount (this dialog stays mounted across open/close;
  // the flag only flips on a real unmount).
  const alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  // Reset the form each time the dialog opens — the parent controls `open`, so this
  // must run on any open transition, not just internal close/open.
  useEffect(() => {
    if (open) {
      setError(null);
      setFields({});
      setPlaidLinkToken(null);
    }
  }, [open]);

  // Only guards accidental dismissal mid-request; open/reset is handled by the effect.
  const setOpen = useCallback(
    (next: boolean) => {
      if (busy) return; // don't dismiss mid-request
      onOpenChange(next);
    },
    [busy, onOpenChange],
  );

  async function run<T>(op: () => Promise<T>, onOk: (r: T) => void, fallback: string) {
    setBusy(true);
    setError(null);
    try {
      const r = await op();
      if (alive.current) onOk(r);
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "integration-connect", step: authMethod });
      if (alive.current) setError(errMsg(err, fallback));
    } finally {
      if (alive.current) setBusy(false);
    }
  }

  function finishDirect() {
    onConnected();
    onOpenChange(false);
  }

  const onApiKey = () =>
    run(
      () =>
        integrationsApi.connect({
          type: "api_key",
          providerId,
          serviceType,
          ecosystemId,
          fields: Object.fromEntries(specFields.map((f) => [f.key, (fields[f.key] ?? "").trim()])),
        }),
      () => finishDirect(),
      "Couldn't connect with those credentials.",
    );

  // app_password (e.g. Bluesky): the saved config holds the handle + app-password, so the
  // connect names the config and the backend sources the creds — nothing is entered here.
  const onAppPassword = () => {
    if (!providerConfigId) return;
    return run(
      () =>
        integrationsApi.connect({
          type: "app_password",
          providerId,
          serviceType,
          ecosystemId,
          providerConfigId,
        }),
      () => finishDirect(),
      "Couldn't connect with the saved credentials.",
    );
  };

  // OAuth: mint the authorize URL, stash the return context under the signed state,
  // then hand the browser to the provider. The page leaves, so `busy` stays set.
  const onOAuth = () => {
    const redirectUri = oauthCallbackUrl();
    const returnTo = currentReturnTo();
    return run(
      () => integrationsApi.getAuthUrl(providerId, { ecosystemId, redirectUri, serviceType }),
      ({ url, state }) => {
        stashPendingConnect(state, {
          authMethod: "oauth",
          providerId,
          serviceType,
          ecosystemId,
          redirectUri,
          returnTo,
        });
        window.location.assign(url);
      },
      "Couldn't start the OAuth flow.",
    );
  };

  // oauth_instance (Mastodon): the saved config holds the instance URL + app creds, so the
  // register names the config and the backend sources them. The register schema still requires
  // a non-empty instanceUrl even though the config path ignores it, so we send the config's.
  const onOAuthInstance = () => {
    // Both are preconditions of the register call — the button is disabled without them, so this
    // is the belt-and-braces guard, not the user-facing message (renderBody carries that).
    if (!providerConfigId || !configInstanceUrl) return;
    const redirectUri = oauthCallbackUrl();
    const returnTo = currentReturnTo();
    return run(
      () =>
        integrationsApi.registerInstance(providerId, {
          ecosystemId,
          instanceUrl: configInstanceUrl,
          redirectUri,
          serviceType,
          providerConfigId,
        }),
      ({ authorizeUrl, state }) => {
        stashPendingConnect(state, {
          authMethod: "oauth_instance",
          providerId,
          serviceType,
          ecosystemId,
          redirectUri,
          returnTo,
        });
        window.location.assign(authorizeUrl);
      },
      "Couldn't start the connection.",
    );
  };

  const onPlaid = () =>
    run(
      // serviceType is min(1)-optional server-side: omit "" and let the backend
      // default to the provider's primary service type.
      () =>
        integrationsApi.createLinkToken(providerId, {
          ecosystemId,
          serviceType: serviceType || undefined,
        }),
      ({ linkToken }) => setPlaidLinkToken(linkToken),
      "Couldn't mint a Plaid Link token.",
    );

  // Plaid Link handed back a public_token — exchange it for the connection.
  const onPlaidSuccess = (publicToken: string) => {
    setPlaidLinkToken(null); // unmount the launcher; the exchange takes over
    void run(
      () =>
        integrationsApi.connect({
          type: "plaid_link",
          providerId,
          serviceType,
          ecosystemId,
          publicToken,
        }),
      () => finishDirect(),
      "Couldn't finish connecting through Plaid.",
    );
  };

  // The user closed Link (or it errored): drop the single-use token so the button
  // mints a fresh one on retry.
  const onPlaidExit = (message: string | null) => {
    setPlaidLinkToken(null);
    if (message) setError(message);
  };

  const fieldId = (suffix: string) => `connect-${providerId}-${suffix}`;

  // A plain function (invoked inline as `{renderBody()}`), NOT a nested component —
  // rendering it as `<Body/>` would remount on every keystroke and drop input focus.
  const renderBody = () => {
    if (blocked) {
      return (
        <p className="text-sm text-apt-text-muted">
          Save this integration&apos;s client configuration first — connecting an account
          needs your ecosystem&apos;s stored credentials.
        </p>
      );
    }
    switch (authMethod) {
      case "api_key": {
        const ready = specFields.every(
          (f) => !f.required || (fields[f.key] ?? "").trim().length > 0,
        );
        return (
          <form
            className="flex flex-col gap-4"
            onSubmit={(e) => {
              e.preventDefault();
              void onApiKey();
            }}
          >
            {specFields.map((f) => (
              <div key={f.key} className="flex flex-col gap-2">
                <Label htmlFor={fieldId(f.key)}>{f.label}</Label>
                <Input
                  id={fieldId(f.key)}
                  type={f.secret ? "password" : "text"}
                  autoComplete="off"
                  value={fields[f.key] ?? ""}
                  placeholder={f.placeholder ?? ""}
                  onChange={(e) => setFields((prev) => ({ ...prev, [f.key]: e.target.value }))}
                />
              </div>
            ))}
            <ErrorText error={error} />
            <div className="flex justify-end gap-2">
              <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={busy}>
                Cancel
              </Button>
              <Button type="submit" disabled={busy || !ready}>
                {busy ? "Connecting…" : "Connect"}
              </Button>
            </div>
          </form>
        );
      }
      case "app_password":
        return (
          <div className="flex flex-col gap-4">
            <p className="text-sm text-apt-text-muted">
              {configIdentifier ? (
                <>
                  Connect{" "}
                  <span className="font-medium text-apt-text">{configIdentifier}</span> using the
                  app password saved in this integration.
                </>
              ) : (
                <>Connect using the credentials saved in this integration.</>
              )}
            </p>
            <ErrorText error={error} />
            <div className="flex justify-end gap-2">
              <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={busy}>
                Cancel
              </Button>
              <Button type="button" onClick={() => void onAppPassword()} disabled={busy}>
                {busy ? "Connecting…" : "Connect"}
              </Button>
            </div>
          </div>
        );
      case "oauth":
        return (
          <div className="flex flex-col gap-4">
            <p className="text-sm text-apt-text-muted">
              You&apos;ll be sent to {displayName} to authorize access, then returned here.
            </p>
            <ErrorText error={error} />
            <div className="flex justify-end gap-2">
              <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={busy}>
                Cancel
              </Button>
              <Button type="button" onClick={() => void onOAuth()} disabled={busy}>
                {busy ? "Redirecting…" : `Continue to ${displayName}`}
              </Button>
            </div>
          </div>
        );
      case "oauth_instance":
        // The register call sends the CONFIG's instanceUrl (the schema requires a non-empty one,
        // and it is where the user is about to be sent). A config saved without it can only fail
        // server-side with an opaque 400, so say what's missing and keep Continue disabled.
        return (
          <div className="flex flex-col gap-4">
            {configInstanceUrl ? (
              <p className="text-sm text-apt-text-muted">
                You&apos;ll be sent to{" "}
                <span className="font-medium text-apt-text">{configInstanceUrl}</span> to authorize
                access, then returned here.
              </p>
            ) : (
              <p className="text-sm text-apt-text-muted">
                This integration has no instance URL saved, so there&apos;s nowhere to send you.
                Add the server address (e.g. https://mastodon.social) to the integration and save
                it, then connect.
              </p>
            )}
            <ErrorText error={error} />
            <div className="flex justify-end gap-2">
              <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={busy}>
                Cancel
              </Button>
              <Button
                type="button"
                onClick={() => void onOAuthInstance()}
                disabled={busy || !configInstanceUrl}
              >
                {busy ? "Redirecting…" : "Continue"}
              </Button>
            </div>
          </div>
        );
      case "plaid_link":
        return (
          <div className="flex flex-col gap-4">
            <p className="text-sm text-apt-text-muted">
              {displayName} connects through Plaid Link — a secure window where you pick
              your institution and sign in. Nothing is stored until Link finishes.
            </p>
            {plaidLinkToken ? (
              <PlaidLinkLauncher
                token={plaidLinkToken}
                onSuccess={onPlaidSuccess}
                onExit={onPlaidExit}
              />
            ) : (
              <ErrorText error={error} />
            )}
            <div className="flex justify-end gap-2">
              <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={busy}>
                Cancel
              </Button>
              <Button
                type="button"
                onClick={() => void onPlaid()}
                disabled={busy || plaidLinkToken !== null}
              >
                {busy ? "Connecting…" : plaidLinkToken ? "Plaid Link open…" : "Connect with Plaid"}
              </Button>
            </div>
          </div>
        );
      default:
        return <p className="text-sm text-apt-text-muted">This provider can&apos;t be connected here.</p>;
    }
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Connect {displayName}</DialogTitle>
          <DialogDescription>Link a {displayName} account to this ecosystem.</DialogDescription>
        </DialogHeader>
        {renderBody()}
      </DialogContent>
    </Dialog>
  );
}
