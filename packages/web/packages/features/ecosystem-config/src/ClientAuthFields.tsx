"use client";

import type { ReactNode } from "react";

import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Switch } from "@agenticdevelopertoolkit/ui/components/switch";
import { DetailSection } from "@agentic-toolkit/resource";
import type { SignupMode } from "@agentic-toolkit/data/ecosystems";
import type {
  ApplicationPlatform,
  AuthProviderChoice,
  ClientAuthPolicy,
} from "@agentic-toolkit/data/ecosystem-config";
import { UrlRowsEditor } from "./UrlRowsEditor";
import { blankRegistration, providerOn, toggleProvider, type RegistrationDraft } from "./client-auth-model";

const SIGNUP_MODES: { value: SignupMode; label: string; help: string }[] = [
  { value: "open", label: "Open", help: "Anyone who can sign in can create an account." },
  { value: "invite_only", label: "Invite only", help: "Only people you've invited can create an account. Invitations are under Users." },
  { value: "closed", label: "Closed", help: "No new accounts can be created." },
];

/** One labelled row with its control on the right. */
function SettingRow({
  id,
  label,
  help,
  children,
}: {
  id: string;
  label: string;
  help: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between sm:gap-6">
      <div className="min-w-0">
        <Label htmlFor={id} className="text-sm font-medium text-apt-text">
          {label}
        </Label>
        <p className="mt-0.5 text-xs text-apt-text-muted">{help}</p>
      </div>
      {children}
    </div>
  );
}

/**
 * The sign-in POLICY controls: sign-in, email + password, sign-up mode, and a switch per OAuth
 * provider. The ecosystem's Settings pane draws these; the policy is the ecosystem's alone.
 * Controlled; `idPrefix` keeps two sets on one page from sharing element ids.
 */
export function ClientAuthPolicyFields({
  policy,
  providers,
  onChange,
  idPrefix,
}: {
  policy: ClientAuthPolicy;
  providers: readonly AuthProviderChoice[];
  onChange: (patch: Partial<ClientAuthPolicy>) => void;
  idPrefix: string;
}) {
  const onCount = providers.filter((p) => providerOn(policy, p.slug)).length;
  return (
    <>
      <DetailSection title="Sign-in">
        <Card>
          <CardContent className="flex flex-col gap-5">
            <SettingRow
              id={`${idPrefix}-login`}
              label="Allow sign-in"
              help="When off, no one can sign in."
            >
              <Switch
                id={`${idPrefix}-login`}
                checked={policy.loginEnabled}
                onCheckedChange={(loginEnabled) => onChange({ loginEnabled })}
              />
            </SettingRow>
            <SettingRow
              id={`${idPrefix}-password`}
              label="Email and password"
              help="Let people sign in and sign up with an email address and a password."
            >
              <Switch
                id={`${idPrefix}-password`}
                checked={policy.passwordEnabled}
                onCheckedChange={(passwordEnabled) => onChange({ passwordEnabled })}
              />
            </SettingRow>
          </CardContent>
        </Card>
      </DetailSection>

      <DetailSection title="Sign-up">
        <Card>
          <CardContent>
            <SettingRow
              id={`${idPrefix}-signup`}
              label="Sign-up mode"
              help={SIGNUP_MODES.find((m) => m.value === policy.signupMode)?.help}
            >
              <Select
                id={`${idPrefix}-signup`}
                value={policy.signupMode}
                onChange={(e) => onChange({ signupMode: e.target.value as SignupMode })}
              >
                {SIGNUP_MODES.map((m) => (
                  <option key={m.value} value={m.value}>
                    {m.label}
                  </option>
                ))}
              </Select>
            </SettingRow>
          </CardContent>
        </Card>
      </DetailSection>

      <DetailSection title="OAuth providers">
        <Card>
          <CardContent className="flex flex-col gap-5">
            {providers.length === 0 ? (
              <p className="text-sm text-apt-text-muted">No OAuth providers are configured.</p>
            ) : (
              providers.map((p) => {
                const on = providerOn(policy, p.slug);
                return (
                  <SettingRow
                    key={p.slug}
                    id={`${idPrefix}-provider-${p.slug}`}
                    label={p.name}
                    help={on && onCount === 1 ? "At least one provider stays on." : `Sign in with ${p.name}.`}
                  >
                    <Switch
                      id={`${idPrefix}-provider-${p.slug}`}
                      checked={on}
                      disabled={on && onCount === 1}
                      onCheckedChange={(next) =>
                        onChange({ allowedProviders: toggleProvider(policy, providers, p.slug, next) })
                      }
                    />
                  </SettingRow>
                );
              })
            )}
          </CardContent>
        </Card>
      </DetailSection>
    </>
  );
}

/** What each platform's redirect URIs may be, for the editor's help line and placeholder. */
const REDIRECT_HELP: Record<ApplicationPlatform | "any", { help: string; placeholder: string }> = {
  web: {
    help: "Where your site receives the sign-in result: https, or http on localhost while developing.",
    placeholder: "https://myapp.com/callback",
  },
  native: {
    help: "Where your app receives the sign-in result: a custom scheme such as com.example.app:/callback, a universal or app link (https), or a loopback address.",
    placeholder: "com.example.app:/callback",
  },
  any: {
    help: "Where your app receives the sign-in result. Native apps can use a custom scheme such as com.example.app:/callback.",
    placeholder: "https://myapp.com/callback",
  },
};

/**
 * A LOGIN REGISTRATION: the OIDC client an app signs its customers in through. It shows the
 * client id (read-only, assigned by the server), the redirect URIs, and the allowed return
 * origins. `registration: null` means none, and the section offers to create one. Remove sets it
 * back to null. Both take effect on Save.
 *
 * `platform` is the application's: a native app has no return origins, so that editor is not
 * drawn, and the redirect help says what each platform accepts. Absent (the ecosystem's own
 * registration) draws both editors.
 *
 * The URL editors keep their own rows (see UrlRowsEditor). `generation` is part of their key, so
 * a Cancel or a save that re-seeds the draft also resets the rows.
 */
export function LoginRegistrationFields({
  registration,
  clientId,
  onChange,
  idPrefix,
  generation,
  title = "Login registration",
  emptyText,
  platform,
  error,
}: {
  registration: RegistrationDraft | null;
  /** The saved registration's client id, or null before it is saved. */
  clientId: string | null;
  onChange: (next: RegistrationDraft | null) => void;
  idPrefix: string;
  generation: number;
  title?: string;
  emptyText: ReactNode;
  platform?: ApplicationPlatform;
  /** A failed save's message, drawn inside the card. */
  error?: string | null;
}) {
  const redirect = REDIRECT_HELP[platform ?? "any"];
  return (
    <DetailSection title={title}>
      <Card>
        <CardContent className="flex flex-col gap-5">
          {registration === null ? (
            <div className="flex flex-col items-start gap-3">
              <p className="text-sm text-apt-text-muted">{emptyText}</p>
              <Button type="button" variant="outline" size="sm" onClick={() => onChange(blankRegistration(platform))}>
                Create login registration
              </Button>
            </div>
          ) : (
            <>
              <div className="flex flex-col gap-2">
                <Label htmlFor={`${idPrefix}-client-id`}>Client id</Label>
                {clientId ? (
                  <div className="flex items-center gap-2">
                    <Input
                      id={`${idPrefix}-client-id`}
                      readOnly
                      value={clientId}
                      onFocus={(e) => e.currentTarget.select()}
                    />
                    <Button
                      type="button"
                      variant="secondary"
                      size="sm"
                      onClick={() => void navigator.clipboard?.writeText(clientId)}
                    >
                      Copy
                    </Button>
                  </div>
                ) : (
                  <p id={`${idPrefix}-client-id`} className="text-sm text-apt-text-muted">
                    Assigned when you save.
                  </p>
                )}
                <p className="text-xs text-apt-text-muted">
                  The client id your app sends as <code>client_id</code>.
                </p>
              </div>

              <UrlRowsEditor
                key={`redirects-${generation}`}
                label="Redirect URIs"
                helpText={redirect.help}
                placeholder={redirect.placeholder}
                addLabel="Add redirect URI"
                removeLabel="Remove redirect URI"
                values={registration.redirectUris}
                onChange={(redirectUris) => onChange({ ...registration, redirectUris })}
              />

              {platform !== "native" && (
                <UrlRowsEditor
                  key={`origins-${generation}`}
                  label="Allowed return origins"
                  helpText={
                    <>
                      The origins your app may finish sign-in on, e.g. <code>https://myapp.com</code>.
                    </>
                  }
                  placeholder="https://myapp.com"
                  addLabel="Add origin"
                  removeLabel="Remove origin"
                  values={registration.allowedReturnOrigins}
                  onChange={(allowedReturnOrigins) => onChange({ ...registration, allowedReturnOrigins })}
                />
              )}

              <div>
                <Button type="button" variant="destructive-ghost" size="sm" onClick={() => onChange(null)}>
                  Remove login registration
                </Button>
              </div>
            </>
          )}
          <ErrorText error={error} />
        </CardContent>
      </Card>
    </DetailSection>
  );
}
