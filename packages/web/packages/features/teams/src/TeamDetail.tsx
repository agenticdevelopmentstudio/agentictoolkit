"use client";

import { useId } from "react";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import type { Team, TeamInput } from "@agentic-toolkit/data/teams";
import { validateTeamIdentifier } from "@agentic-toolkit/data/teams";
import { DetailSection } from "@agentic-toolkit/resource";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";

export function teamBlank(): TeamInput {
  return { displayName: "", identifier: "" };
}

export function teamToInput(t: Team): TeamInput {
  return { displayName: t.displayName, identifier: t.identifier };
}

/** Returns an error message, or null when the draft is valid.
 *
 *  `storedIdentifier` is the identifier already on the record being edited. It is exempt from the
 *  reverse-domain FORMAT rule: the backend provisions teams with plain slugs (`participants`,
 *  `admins`), and requiring the user to rename one before any other field could be saved left
 *  Save permanently disabled on exactly the teams every workspace has. A changed identifier is
 *  still held to the format. */
export function teamValidate(
  draft: TeamInput,
  takenIdentifiers: string[],
  storedIdentifier?: string,
): string | null {
  if (!draft.displayName.trim()) return "Display name is required.";
  const id = draft.identifier.trim();
  const idErr = id && id === storedIdentifier ? null : validateTeamIdentifier(id);
  if (idErr) return idErr;
  if (takenIdentifiers.includes(id)) return `Identifier "${id}" is already in use.`;
  return null;
}

/**
 * Controlled team form — fields only. Save/Cancel/Delete live in the button bar
 * (Settings pane) or the dialog footer (New Team). With `title` the fields are
 * wrapped in a titled DetailSection (the pane); without it they render bare (the
 * create dialog). Field ids are namespaced with useId() so the pane's form and
 * the dialog's — both mounted at once — don't collide on duplicate ids.
 */
export function TeamDetail({
  title,
  draft,
  onChange,
  error,
}: {
  title?: string;
  draft: TeamInput;
  onChange: (next: TeamInput) => void;
  error?: string | null;
}) {
  const uid = useId();
  const nameId = `${uid}-name`;
  const identifierId = `${uid}-identifier`;

  function set<K extends keyof TeamInput>(key: K, value: string) {
    onChange({ ...draft, [key]: value });
  }

  const body = (
    <Card>
      <CardContent className="flex flex-col gap-5">
        <div className="flex flex-col gap-2">
          <Label htmlFor={nameId}>Display name</Label>
          <Input
            id={nameId}
            placeholder="Platform Team"
            value={draft.displayName}
            onChange={(e) => set("displayName", e.target.value)}
          />
        </div>
        <div className="flex flex-col gap-2">
          <Label htmlFor={identifierId}>Identifier</Label>
          <Input
            id={identifierId}
            placeholder="com.example.platform"
            value={draft.identifier}
            onChange={(e) => set("identifier", e.target.value.toLowerCase())}
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
          />
          <p className="text-xs text-apt-text-muted">
            Unique reverse-domain string.
          </p>
        </div>

        <ErrorText error={error} />
      </CardContent>
    </Card>
  );

  return title ? <DetailSection title={title}>{body}</DetailSection> : body;
}
