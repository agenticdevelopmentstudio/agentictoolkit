"use client";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import type { RequestBody, SuccessBody } from "@agentic-toolkit/adh-api-types";
import { authedJson, authedRequest } from "./http";

// ── Providers ────────────────────────────────────────────────────────────

// Spec-typed responses (the serializers in the backend's oauth/repo.ts) AND the
// create/update request bodies (the zod schemas in oauthAdmin.ts) — all derived
// from the OpenAPI spec now, so a backend change to either side fails this file's
// tsc instead of at runtime. (Previously the request shapes + IdentityMapping were
// hand-written; providerBody was enriched so they can come off the spec.)
export type OAuthProvider = SuccessBody<"/oauth/providers", "get">[number];
export type ProviderTemplate =
  SuccessBody<"/oauth/provider-templates", "get">["templates"][string];
export type CreateProviderInput = RequestBody<"/oauth/providers", "post">;
export type UpdateProviderInput = RequestBody<"/oauth/providers/{slug}", "patch">;

export function useProviderTemplates() {
  return useQuery({
    queryKey: ["admin", "oauth", "provider-templates"],
    queryFn: () =>
      authedJson<{ templates: Record<string, ProviderTemplate> }>(
        "/api/oauth/provider-templates",
      ),
  });
}

export function useProviders() {
  return useQuery({
    queryKey: ["admin", "oauth", "providers"],
    queryFn: () => authedJson<OAuthProvider[]>("/api/oauth/providers"),
  });
}

export function useProvider(slug: string) {
  return useQuery({
    queryKey: ["admin", "oauth", "providers", slug],
    queryFn: () =>
      authedJson<OAuthProvider>(`/api/oauth/providers/${slug}`),
    enabled: !!slug,
  });
}

export function useCreateProvider() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: CreateProviderInput) =>
      authedJson<OAuthProvider>("/api/oauth/providers", {
        method: "POST",
        body: JSON.stringify(input),
      }),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["admin", "oauth", "providers"] }),
  });
}

export function useUpdateProvider() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ slug, ...input }: UpdateProviderInput & { slug: string }) =>
      authedJson<OAuthProvider>(`/api/oauth/providers/${slug}`, {
        method: "PATCH",
        body: JSON.stringify(input),
      }),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["admin", "oauth", "providers"] }),
  });
}

export function useDeleteProvider() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (slug: string) =>
      authedRequest(`/api/oauth/providers/${slug}`, { method: "DELETE" }),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["admin", "oauth", "providers"] }),
  });
}

// ── Clients ──────────────────────────────────────────────────────────────

// Spec-typed responses + requests. `defaultTenantId` was a drift — the backend
// field is `defaultEcosystemId` (so the old create-client form silently posted the
// wrong key and the create 400'd); RequestBody forces the correct name.
export type OAuthClient = SuccessBody<"/oauth/clients", "get">[number];
export type ClientShowResponse = SuccessBody<"/oauth/clients/{slug}", "get">;
export type ClientLinkedProvider = ClientShowResponse["providers"][number];
export type CreateClientInput = RequestBody<"/oauth/clients", "post">;
export type CreateClientResponse = SuccessBody<"/oauth/clients", "post", 201>;
export type UpdateClientInput = Partial<RequestBody<"/oauth/clients", "post">>;

export interface LinkProviderInput {
  clientIdOverride?: string;
  clientSecretOverride?: string;
}

export type LinkProviderResponse = SuccessBody<
  "/oauth/clients/{slug}/providers/{providerSlug}",
  "put"
>;
export type RotateAppTokenResponse = SuccessBody<
  "/oauth/clients/{slug}/rotate-token",
  "post"
>;

export function useClients() {
  return useQuery({
    queryKey: ["admin", "oauth", "clients"],
    queryFn: () => authedJson<OAuthClient[]>("/api/oauth/clients"),
  });
}

export function useClient(slug: string) {
  return useQuery({
    queryKey: ["admin", "oauth", "clients", slug],
    queryFn: () =>
      authedJson<ClientShowResponse>(`/api/oauth/clients/${slug}`),
    enabled: !!slug,
  });
}

export function useCreateClient() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: CreateClientInput) =>
      authedJson<CreateClientResponse>("/api/oauth/clients", {
        method: "POST",
        body: JSON.stringify(input),
      }),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["admin", "oauth", "clients"] }),
  });
}

export function useUpdateClient() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ slug, ...input }: UpdateClientInput & { slug: string }) =>
      authedJson<OAuthClient>(`/api/oauth/clients/${slug}`, {
        method: "PATCH",
        body: JSON.stringify(input),
      }),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["admin", "oauth", "clients"] }),
  });
}

export function useDeleteClient() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (slug: string) =>
      authedRequest(`/api/oauth/clients/${slug}`, { method: "DELETE" }),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["admin", "oauth", "clients"] }),
  });
}

export function useLinkProvider() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({
      clientSlug,
      providerSlug,
      ...input
    }: LinkProviderInput & { clientSlug: string; providerSlug: string }) =>
      authedJson<LinkProviderResponse>(
        `/api/oauth/clients/${clientSlug}/providers/${providerSlug}`,
        {
          method: "PUT",
          body: JSON.stringify(input),
        },
      ),
    onSuccess: (_, vars) =>
      qc.invalidateQueries({
        queryKey: ["admin", "oauth", "clients", vars.clientSlug],
      }),
  });
}

export function useUnlinkProvider() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({
      clientSlug,
      providerSlug,
    }: {
      clientSlug: string;
      providerSlug: string;
    }) =>
      authedRequest(
        `/api/oauth/clients/${clientSlug}/providers/${providerSlug}`,
        { method: "DELETE" },
      ),
    onSuccess: (_, vars) =>
      qc.invalidateQueries({
        queryKey: ["admin", "oauth", "clients", vars.clientSlug],
      }),
  });
}

export function useRotateClientToken() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (slug: string) =>
      authedJson<RotateAppTokenResponse>(
        `/api/oauth/clients/${slug}/rotate-token`,
        { method: "POST" },
      ),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["admin", "oauth", "clients"] }),
  });
}

// ── Auth Methods ─────────────────────────────────────────────────────────

// Spec-typed: a row of GET /auth/methods (AuthMethodSetting = { method, enabled }).
export type AuthMethod = SuccessBody<"/auth/methods", "get">[number];

export function useAuthMethods() {
  return useQuery({
    queryKey: ["admin", "auth-methods"],
    queryFn: () => authedJson<AuthMethod[]>("/api/auth/methods"),
  });
}

export function useUpdateAuthMethod() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ method, enabled }: AuthMethod) =>
      authedJson(`/api/auth/methods/${method}`, {
        method: "PATCH",
        body: JSON.stringify({ enabled }),
      }),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["admin", "auth-methods"] }),
  });
}
