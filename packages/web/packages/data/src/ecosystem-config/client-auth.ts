"use client";

// CLIENT AUTH for one ecosystem and for one application: how the ecosystem's customers sign in
// to the developer's own apps (docs/designs/client-auth.md in adhbackend). There is one policy
// per ecosystem (Users ▸ Authentication), and it governs every sign-in. An application may have
// a login registration of its own, shaped by its platform (web or native).
//
//   GET/PUT /api/ecosystem/client-auth/:ecosystemId            → EcosystemClientAuth
//   GET/PUT /api/ecosystem/applications/:appId/client-auth     → ApplicationClientAuth
//
// A PUT sends only the keys it changes, and `registration: null` removes a login registration.
// The wire types are hand-written, for the reason feature-flags.ts states.

import { authedJson } from "../http";
import { compact, enc } from "../client-helpers";
import type { AuthSettings } from "../ecosystems/ecosystems";

/** The sign-in policy. It has the same shape as the ecosystem's auth settings. */
export type ClientAuthPolicy = AuthSettings;

/** A LOGIN REGISTRATION: the OIDC client an app signs its customers in through. The server
 *  assigns the client id. */
export interface LoginRegistration {
  clientId: string;
  allowedReturnOrigins: string[];
  redirectUris: string[];
}

export type LoginRegistrationInput = Omit<LoginRegistration, "clientId">;

/** An OAuth provider the platform has configured, which an ecosystem may switch on or off. */
export interface AuthProviderChoice {
  slug: string;
  name: string;
}

export interface EcosystemClientAuth {
  settings: ClientAuthPolicy;
  registration: LoginRegistration | null;
  providers: AuthProviderChoice[];
}

export interface EcosystemClientAuthUpdate {
  settings?: Partial<ClientAuthPolicy>;
  registration?: LoginRegistrationInput | null;
}

/**
 * What an application is, for signing in. Both sign in as public PKCE clients; the platform
 * decides what their registration accepts. A web app redirects to https (or http on a loopback
 * host) and may list return origins; a native app may also redirect to a custom scheme, and has
 * no return origins. Matches the backend `applications_platform_chk`.
 */
export type ApplicationPlatform = "web" | "native";

export const APPLICATION_PLATFORMS: readonly ApplicationPlatform[] = ["web", "native"];

export interface ApplicationClientAuth {
  /** Set on the application itself (its settings), not here. */
  platform: ApplicationPlatform;
  /** null means the application has no registration of its own and signs in through the
   *  ecosystem's. */
  registration: LoginRegistration | null;
}

export interface ApplicationClientAuthUpdate {
  registration: LoginRegistrationInput | null;
}

const ecosystemPath = (ecosystemId: string) => `/api/ecosystem/client-auth/${enc(ecosystemId)}`;
const applicationPath = (appId: string) => `/api/ecosystem/applications/${enc(appId)}/client-auth`;

export const clientAuthApi = {
  /** The ecosystem's settings, its login registration, and the providers it can switch on. */
  async ecosystem(ecosystemId: string): Promise<EcosystemClientAuth> {
    return authedJson<EcosystemClientAuth>(ecosystemPath(ecosystemId));
  },

  /** `compact` drops the keys left undefined but keeps an explicit `registration: null`. */
  async updateEcosystem(
    ecosystemId: string,
    update: EcosystemClientAuthUpdate,
  ): Promise<EcosystemClientAuth> {
    return authedJson<EcosystemClientAuth>(ecosystemPath(ecosystemId), {
      method: "PUT",
      body: JSON.stringify(compact(update)),
    });
  },

  async application(appId: string): Promise<ApplicationClientAuth> {
    return authedJson<ApplicationClientAuth>(applicationPath(appId));
  },

  async updateApplication(
    appId: string,
    update: ApplicationClientAuthUpdate,
  ): Promise<ApplicationClientAuth> {
    return authedJson<ApplicationClientAuth>(applicationPath(appId), {
      method: "PUT",
      body: JSON.stringify(compact(update)),
    });
  },
};
