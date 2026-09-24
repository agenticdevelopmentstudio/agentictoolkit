"use client";

import { useCallback } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { PrivacyLevelSelect } from "@agenticdevelopertoolkit/ui/components/privacy-level-select";
import { ContactsCard } from "../notifications/ContactsCard";
import {
  getPrivacyGrants,
  setPrivacyGrant,
  resolvePrivacyLevel,
  PRIVACY_KEY,
  type PrivacyLevel,
} from "@agentic-toolkit/data/profile";
import { SettingsBody } from "@agentic-toolkit/resource";
import type { ContactMethod } from "../api/account";

// ── Component ──────────────────────────────────────────────────────────────────

export function ContactInfoPanel() {
  const qc = useQueryClient();

  const privacyQuery = useQuery({
    queryKey: PRIVACY_KEY,
    queryFn: getPrivacyGrants,
    retry: false,
  });

  // Not `?? []` here: a fresh empty array per render would defeat the useCallback below.
  const grants = privacyQuery.data;

  const privacyMutation = useMutation({
    mutationFn: ({ id, level }: { id: string; level: PrivacyLevel }) =>
      setPrivacyGrant("contact_methods", id, level),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: PRIVACY_KEY });
    },
  });

  // Stable across renders that change nothing it reads: ContactsCard builds its table columns from
  // it, and a fresh function every render would rebuild them every render.
  const { mutate: setLevel, isPending: levelPending } = privacyMutation;
  const rowExtra = useCallback((contact: ContactMethod) => {
    const level = resolvePrivacyLevel(grants ?? [], "contact_methods", contact.id);
    const typeLabel = contact.type === "email" ? "Email" : "Phone";
    return (
      <div className="w-36 shrink-0">
        <PrivacyLevelSelect
          value={level}
          onChange={(next) => setLevel({ id: contact.id, level: next })}
          ariaLabel={`${typeLabel} ${contact.value} visibility`}
          disabled={levelPending}
        />
      </div>
    );
  }, [grants, setLevel, levelPending]);

  // Full width: this topic IS a table, and a form-width cap truncates the columns it was resized
  // to show. `hideSectionTitle` because the registry's FeatureTitle already says "Contacts".
  return (
    <SettingsBody width="full">
      <ContactsCard rowExtra={rowExtra} hideSectionTitle />
    </SettingsBody>
  );
}
