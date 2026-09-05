"use client";

import { useMemo, type ReactElement } from "react";
import { CircleUser } from "lucide-react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Field, type TopicLevel } from "@agentic-toolkit/ui/blocks";
import { Select } from "@agentic-toolkit/ui/components/select";
import { useSettingsEntityLevel } from "../settings-level";
import { useEditorMutations } from "./use-editor-mutations";
import { useDraftForSelection } from "./use-draft-for-selection";
import { EntityEditorShell, SectionErrorText, SectionPlaceholder } from "./section-chrome";

interface UserRow {
  id: string;
  email: string;
  displayName?: string | null;
  role: "pending" | "viewer" | "admin";
}

const NO_USERS: UserRow[] = [];

/**
 * Admin-only "Users" section of the Config panel. Fetches /api/users
 * (admin-gated) and publishes the roster as the board hierarchy's entity level
 * (`/settings/users/<id>`); the leaf edits one user's role (PATCH
 * /api/users/:id) or deletes them (DELETE /api/users/:id). No "new" action —
 * users self-register. 409 responses surface their server-side message inline.
 */
export function UsersSection({
  selectedId,
  onNavigate,
}: {
  /** URL-selected user id (`/settings/users/<id>`), owned by the board level. */
  selectedId: string | null;
  onNavigate: (id: string | null) => void;
}): ReactElement {
  const queryClient = useQueryClient();
  const { busy, error, setError, run } = useEditorMutations();

  const { data, error: queryError } = useQuery<UserRow[]>({
    queryKey: ["status-users"],
    queryFn: () => fetch("/api/users").then((r) => r.json()) as Promise<UserRow[]>,
  });
  const users = data ?? NO_USERS;

  const current = selectedId ? (users.find((u) => u.id === selectedId) ?? null) : null;

  // The draft is just the role — same shared render-phase load as the other
  // sections (waits for the row so deep-link hard reloads hydrate once the
  // query lands, and leaving Settings never wipes an unsaved change).
  const { draft: draftRole, setDraft: setDraftRole, discardDraft } = useDraftForSelection<UserRow, UserRow["role"]>({
    selectedId,
    current,
    initial: () => "pending",
    load: (u) => u.role,
  });

  const dirty = !!current && draftRole !== current.role;

  // Throws on !ok so useEditorMutations surfaces the server's message (409 etc).
  async function request(method: "PATCH" | "DELETE", id: string, body?: unknown): Promise<void> {
    const res = await fetch(`/api/users/${id}`, {
      method,
      ...(body !== undefined
        ? { headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) }
        : {}),
    });
    if (!res.ok) {
      const errBody = (await res.json().catch(() => ({}))) as { error?: string; message?: string };
      throw new Error(errBody.error ?? errBody.message ?? `Request failed (${res.status})`);
    }
    await queryClient.invalidateQueries({ queryKey: ["status-users"] });
  }

  function save(): void {
    if (!current) return;
    void run(() => request("PATCH", current.id, { role: draftRole }));
  }
  function del(): void {
    if (!current) return;
    void run(async () => {
      await request("DELETE", current.id);
      onNavigate(null);
    });
  }

  // Publish the roster as the hierarchy's entity level; the editor is the leaf.
  // A failed fetch swaps the rail's empty label so an empty list never misreads
  // as "there are zero users".
  const level = useMemo<TopicLevel>(
    () => ({
      id: "roster-users",
      title: "Users",
      items: users.map((u) => ({
        id: u.id,
        label: u.displayName || u.email,
        sublabel: u.role,
        icon: <CircleUser size={16} aria-hidden />,
      })),
      selectedId,
      onSelect: (id) => {
        setError(null);
        onNavigate(id);
      },
      onClear: () => {
        setError(null);
        onNavigate(null);
      },
      emptyLabel: queryError ? "Failed to load users." : "No users found.",
    }),
    [users, selectedId, onNavigate, setError, queryError],
  );
  useSettingsEntityLevel(level);

  if (queryError instanceof Error) {
    return <SectionErrorText>{queryError.message}</SectionErrorText>;
  }
  if (!current) {
    return <SectionPlaceholder>Select a user to manage their role.</SectionPlaceholder>;
  }
  return (
    <EntityEditorShell
      onCancel={() => {
        setError(null);
        discardDraft();
        onNavigate(null);
      }}
      onSave={save}
      canSave={dirty && !busy}
      saving={busy}
      onDelete={del}
      canDelete={true}
      deleteConfirm={{ title: `Delete user "${current.displayName || current.email}"?` }}
      error={error}
    >
      <div className="flex max-w-md flex-col gap-3 p-4 font-mono">
        <div className="flex flex-col">
          <span className="text-sm text-apt-text">{current.displayName || current.email}</span>
          {current.displayName ? <span className="text-xs text-apt-text-muted">{current.email}</span> : null}
        </div>
        <Field label="Role" className="max-w-40">
          <Select
            value={draftRole}
            aria-label={`Role for ${current.email}`}
            onChange={(e) => setDraftRole(e.target.value as UserRow["role"])}
          >
            <option value="pending">pending</option>
            <option value="viewer">viewer</option>
            <option value="admin">admin</option>
          </Select>
        </Field>
      </div>
    </EntityEditorShell>
  );
}
