"use client";

import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import type { EcosystemUser, EcosystemUserInput } from "../api/customers";
import { DetailSection } from "@agentic-toolkit/resource";

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export function userBlank(): EcosystemUserInput {
  return { email: "", displayName: "", externalId: "", slug: "", avatarUrl: "" };
}

export function userToInput(u: EcosystemUser): EcosystemUserInput {
  return {
    email: u.email,
    displayName: u.displayName,
    externalId: u.externalId,
    slug: u.slug,
    avatarUrl: u.avatarUrl,
  };
}

/** Returns an error message, or null when the draft is valid. */
export function userValidate(
  draft: EcosystemUserInput,
  takenEmails: string[] = [],
): string | null {
  const email = draft.email.trim();
  if (!email) return "Email is required.";
  if (!EMAIL_RE.test(email)) return "Enter a valid email address.";
  if (takenEmails.some((e) => e.toLowerCase() === email.toLowerCase()))
    return `A user with email "${email}" already exists.`;
  // The backend has no default for the handle any more — a name is chosen, never minted —
  // so a create without one is refused. Say so here rather than as a 400 after Save.
  if (!draft.slug.trim()) return "Handle is required.";
  return null;
}

/**
 * Controlled ecosystem-user form — fields only. Save/Cancel/Delete live in the
 * MasterDetailLayout button bar; the pane owns the draft + dirty/validity state.
 */
export function UserDetail({
  title,
  draft,
  onChange,
  error,
}: {
  title: string;
  draft: EcosystemUserInput;
  onChange: (next: EcosystemUserInput) => void;
  error?: string | null;
}) {
  function set<K extends keyof EcosystemUserInput>(key: K, value: string) {
    onChange({ ...draft, [key]: value });
  }

  return (
    <DetailSection title={title}>
      <Card>
        <CardContent className="flex flex-col gap-5">
          <Field
            id="user-email"
            label="Email"
            hint="The identifier this user signs in to the ecosystem with."
            placeholder="person@example.com"
            value={draft.email}
            onChange={(v) => set("email", v)}
          />
          <Field
            id="user-name"
            label="Display name"
            placeholder="Jane Doe"
            value={draft.displayName}
            onChange={(v) => set("displayName", v)}
          />
          <Field
            id="user-external"
            label="External ID"
            hint="Optional — their id in an external identity provider."
            placeholder="auth0|abc123"
            value={draft.externalId}
            onChange={(v) => set("externalId", v)}
          />
          <Field
            id="user-slug"
            label="Handle"
            hint="A short handle for the user — the last part of their address."
            placeholder="jane"
            value={draft.slug}
            onChange={(v) => set("slug", v)}
          />
          <Field
            id="user-avatar"
            label="Avatar URL"
            hint="Optional."
            placeholder="https://…"
            value={draft.avatarUrl}
            onChange={(v) => set("avatarUrl", v)}
          />

          <ErrorText error={error} />
        </CardContent>
      </Card>
    </DetailSection>
  );
}

function Field({
  id,
  label,
  hint,
  placeholder,
  value,
  onChange,
}: {
  id: string;
  label: string;
  hint?: string;
  placeholder?: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <div className="flex flex-col gap-2">
      <Label htmlFor={id}>{label}</Label>
      <Input
        id={id}
        placeholder={placeholder}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
      {hint && <p className="text-xs text-apt-text-muted">{hint}</p>}
    </div>
  );
}
