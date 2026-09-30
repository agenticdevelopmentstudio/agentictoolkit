"use client";

import type { ReactNode } from "react";

import { useResourceItemQuery, useResourceItemWriter } from "@agentic-toolkit/data";
import {
  clientAuthApi,
  type ClientAuthPolicy,
  type EcosystemClientAuth,
} from "@agentic-toolkit/data/ecosystem-config";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import {
  DetailsPane,
  useReportBusy,
  useSettingsDraft,
  type DetailsSection,
} from "@agentic-toolkit/resource";
import { ClientAuthPolicyFields } from "./ClientAuthFields";
import { policyPatch, samePolicy } from "./client-auth-model";

/** The cache key the ecosystem's client auth is read under. An application's override section
 *  reads the same entry for the providers and the ecosystem's settings. */
export const ECOSYSTEM_CLIENT_AUTH_KEY = "ecosystem-client-auth";

const toDraft = (c: EcosystemClientAuth): ClientAuthPolicy => c.settings;

/**
 * An ecosystem's CLIENT AUTH settings (Users ▸ Authentication): how the ecosystem's customers
 * sign in to the apps built on it. It holds the sign-in policy, the sign-up mode and which OAuth
 * providers are on — one config for the whole ecosystem. Login registrations are not here: each
 * application has its own, in its detail (Mike, 2026-09-30).
 *
 * One DetailsPane over `/ecosystem/client-auth/:ecosystemId`. A save sends only the policy fields
 * that changed; it never names the registration, so the server leaves it as it is.
 */
export function ClientAuthSettingsPane({
  ecosystemId,
  help,
}: {
  ecosystemId?: string;
  /** Unused: the breadcrumb names the pane. Kept for the ScopedPane prop shape. */
  title?: ReactNode;
  help?: ReactNode;
}) {
  const {
    item: config,
    error: loadError,
    isFetching,
  } = useResourceItemQuery<EcosystemClientAuth>(
    ECOSYSTEM_CLIENT_AUTH_KEY,
    ecosystemId ?? null,
    clientAuthApi.ecosystem,
  );
  const writeConfig = useResourceItemWriter<EcosystemClientAuth>(ECOSYSTEM_CLIENT_AUTH_KEY);
  useReportBusy(isFetching);

  const draft = useSettingsDraft<EcosystemClientAuth, ClientAuthPolicy>(config, toDraft, samePolicy);

  // Handed to the pane as its own section: this component renders the DetailsPane, so a
  // `useDetailsSection` call here would sit outside the pane's scope.
  const section: DetailsSection = {
    dirty: draft.dirty,
    canSave: true,
    blockedReason: null,
    save: async () => {
      if (!ecosystemId || !draft.draft || !draft.seed) return;
      const settings = policyPatch(draft.draft, draft.seed);
      // Dirty with nothing of this user's to send: the edits were undone while the server copy
      // moved underneath. Adopt the server's copy rather than PUT an empty body (a 400).
      if (!settings) {
        if (config) draft.commit(config);
        return;
      }
      const updated = await clientAuthApi.updateEcosystem(ecosystemId, { settings });
      writeConfig(ecosystemId, updated);
      draft.commit(updated);
    },
    reset: draft.reset,
  };

  const current = draft.draft;
  return (
    <DetailsPane
      help={help}
      section={section}
      api={
        ecosystemId
          ? {
              path: "/ecosystem/client-auth/{ecosystemId}",
              pathValues: { ecosystemId },
              title: "Client auth API",
            }
          : null
      }
    >
      <ErrorText error={loadError} />
      {!current && !loadError && <p className="text-sm text-apt-text-muted">Loading…</p>}
      {current && config && (
        <ClientAuthPolicyFields
          idPrefix="eco-client-auth"
          policy={current}
          providers={config.providers}
          onChange={(patch) => draft.patch(patch)}
        />
      )}
    </DetailsPane>
  );
}
