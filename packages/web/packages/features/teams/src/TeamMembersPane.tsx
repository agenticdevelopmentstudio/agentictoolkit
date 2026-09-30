"use client";

import { useCallback, useState } from "react";
import type { ReactNode } from "react";
import { Bot, Trash2, UserRound } from "lucide-react";

import { useResourceList } from "@agentic-toolkit/data";
import { teamMembersApi, type TeamMember } from "@agentic-toolkit/data/teams";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { api as personaApi, type Persona } from "@agentic-toolkit/data/personas";
import { TopicSelectHint, type TopicDetailItem, type TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import {
  useStackLevel,
  FeatureTitle,
  CreateResourceDialog,
  type TopicLeaf,
} from "@agentic-toolkit/resource";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** The create modal's draft: add EITHER an existing customer by email OR one of the caller's
 *  personas. The two are mutually exclusive — picking one clears the other — and a picked persona
 *  takes precedence at save (mirrors the backend's two add routes). */
interface AddMemberDraft {
  email: string;
  personaId: string;
}

/**
 * Members feature for the ACTIVE team — wired to the backend (api/team-members.ts). A member is
 * either an existing customer (added by email, resolved server-side) or one of the caller's
 * personas (added by key; the backend gates on the persona's may_act 'team' grant). Rows render
 * by kind: a customer shows its email + a person icon, a persona shows its name/slug + a Bot icon.
 *
 * In the one-stack model the members list is a PUBLISHED level (selecting a member deep-links it),
 * and the leaf detail is the member's card (with a Delete button). Adding a member is a MODAL over
 * the stack (HTD recipe `must-create-in-modal`), not a blank leaf — its `+` opens the two-mode add
 * (an email field OR a persona picker). Membership is add/remove, so there is no per-member editor.
 */
export function TeamMembersPane({
  teamId,
  title,
  leaf,
}: {
  teamId?: string;
  /** The pane's own header title (defaults to "Members"). */
  title?: ReactNode;
  /** Deep-linkable member selection (`…/members/<memberId>`). */
  leaf?: TopicLeaf;
}) {
  // Creating a member is a MODAL over the stack, never a blank leaf (HTD recipe
  // `must-create-in-modal`): the `+` opens it, and on save the new member is selected.
  const [newOpen, setNewOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // In-flight guard for the member delete, so a rapid double-click can't fire two DELETEs.
  const [removingMember, setRemovingMember] = useState(false);

  // The members, cached per TEAM: coming back to a team you have already opened paints its members
  // on the first frame and re-reads behind that paint. The team is in the cache key AND in the
  // fetcher, so switching teams reads a different entry rather than showing one team's members
  // under another team's name — the stale-response race the hand-rolled seq counter used to guard.
  //
  // No team means an empty list, not a read: this pane renders under the "All" landing too, where
  // there is nothing to list.
  const loadMembers = useCallback(
    () => (teamId ? teamMembersApi.list(teamId) : Promise.resolve([] as TeamMember[])),
    [teamId],
  );
  const {
    items: members,
    reload: reloadMembers,
    error: loadError,
    isFetching: membersFetching,
  } = useResourceList<TeamMember>(`team:${teamId ?? ""}:members`, loadMembers);

  // The caller's own personas, for the add-persona picker in the create modal. The backend enforces
  // which of them may act for a team (403 on add if not granted), so we list them all. Caller-scoped
  // rather than team-scoped, so its cache key names no team and one read serves every team's modal.
  const { items: personas, error: personasError } = useResourceList<Persona>(
    "personas:mine",
    personaApi.personas.list,
  );

  // Swallowing: both callers below re-read AFTER their own write has already succeeded, so a failed
  // re-read must not be reported as a failed add or remove. The failure still reaches the screen —
  // it lands in the hook's `error`, which the banner renders.
  const refreshMembers = useCallback(() => reloadMembers().catch(() => {}), [reloadMembers]);

  const selectedId = leaf?.leafId ?? null;
  const selected = selectedId
    ? (members ?? []).find((m) => m.id === selectedId) ?? null
    : null;

  // Discriminate on memberKind (robust even while the api-types field is optional): a persona
  // member shows its persona name/slug + a Bot icon; everything else is a customer, labelled by
  // email → display name → raw id (the last for a member outside the caller's ecosystem).
  const isPersona = (m: TeamMember) => m.memberKind === "persona";
  const labelFor = (m: TeamMember) =>
    isPersona(m)
      ? m.personaName ?? m.personaSlug ?? m.userId
      : m.email ?? m.displayName ?? m.userId;
  const iconFor = (m: TeamMember) =>
    isPersona(m) ? <Bot size={16} aria-hidden /> : <UserRound size={16} aria-hidden />;

  async function del() {
    if (!teamId || !selected) return;
    if (removingMember) return;
    setRemovingMember(true);
    try {
      await teamMembersApi.remove(selected.id);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to remove member.");
      return;
    } finally {
      setRemovingMember(false);
    }
    leaf?.onSelect(null);
    refreshMembers();
  }

  // PUBLISH the members as a stack level. The New member affordance is the header `+`.
  const rows: TopicDetailItem[] = (members ?? []).map((m) => ({
    id: m.id,
    label: labelFor(m),
    sublabel: isPersona(m) ? m.personaSlug ?? undefined : undefined,
    icon: iconFor(m),
  }));
  const level: TopicLevel = {
    id: "members-list",
    title: "Members",
    items: rows,
    selectedId,
    onSelect: (id) => leaf?.onSelect(id),
    onClear: () => leaf?.onSelect(null),
    // A failed read leaves `members` null exactly as a pending one does, so "Loading…" alone would
    // spin here forever. The pane's own `ErrorText` says so, but the rail is the merged host stack —
    // it can be on screen with this pane's body nowhere near it, and then the rail is the only
    // thing the user sees.
    emptyLabel:
      members !== null ? "No members yet." : loadError ? "Couldn’t load members." : "Loading…",
    // The spinner in this list's title while a read is in flight — including the re-read behind a
    // cached paint, which is the only signal that rows already on screen are being checked.
    busy: membersFetching,
    // "New member" is a right-justified `+` in the list header; it opens the create modal. Gated on
    // a team being active — there's nothing to add a member to otherwise.
    onNew: teamId ? () => setNewOpen(true) : undefined,
    newLabel: "New member",
  };
  useStackLevel(level);

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <FeatureTitle
        title={title ?? "Members"}
        api={
          teamId
            ? { path: "/team/members", pathValues: {}, queryValues: { teamId }, title: "Team members API" }
            : null
        }
      />
      <section className="flex min-w-0 flex-1 flex-col gap-3 overflow-y-auto px-6 py-8">
        <ErrorText error={error} />
        <ErrorText error={loadError} />
        {selected ? (
          // The member-detail leaf: the member's identity + a Delete action (no rename).
          <div className="flex max-w-md flex-col gap-4">
            <div className="flex items-center gap-3">
              {isPersona(selected) ? (
                <Bot size={20} aria-hidden className="text-apt-text-muted" />
              ) : (
                <UserRound size={20} aria-hidden className="text-apt-text-muted" />
              )}
              <div className="flex min-w-0 flex-col">
                <span className="truncate font-mono text-sm text-apt-text">
                  {labelFor(selected)}
                </span>
                {isPersona(selected) && (
                  <span className="font-mono text-[0.7rem] uppercase tracking-wider text-apt-text-muted">
                    Persona{selected.personaSlug ? ` · ${selected.personaSlug}` : ""}
                  </span>
                )}
              </div>
            </div>
            <Button
              size="sm"
              variant="destructive-ghost"
              onClick={() => void del()}
              disabled={removingMember}
              className="self-start"
            >
              <Trash2 data-icon="inline-start" />
              Remove from team
            </Button>
          </div>
        ) : members === null ? (
          <p className="text-sm text-apt-text-muted">Loading…</p>
        ) : (
          <TopicSelectHint title="Select a member, or add one.">
            Use “New member” to add a customer by email or one of your personas.
          </TopicSelectHint>
        )}
      </section>

      {/* Create is a scoped modal: add an existing customer by email, OR one of the caller's
          personas. The two are mutually exclusive (picking one clears the other); a picked persona
          wins at save, matching the backend's two add routes. */}
      {newOpen && (
        <CreateResourceDialog<AddMemberDraft, TeamMember>
          ariaLabel="New member"
          heading="New member"
          blank={() => ({ email: "", personaId: "" })}
          validate={(d) =>
            d.personaId
              ? null
              : EMAIL_RE.test(d.email.trim().toLowerCase())
                ? null
                : "Enter a valid email address, or pick a persona."
          }
          create={(d) =>
            d.personaId
              ? teamMembersApi.addPersona(teamId ?? "", d.personaId)
              : teamMembersApi.add(teamId ?? "", d.email.trim().toLowerCase())
          }
          onClose={() => setNewOpen(false)}
          onCreated={(member) => {
            setNewOpen(false);
            refreshMembers();
            leaf?.onSelect(member.id);
          }}
          renderForm={(draft, onChange, formError) => (
            <div className="flex flex-col gap-6">
              <Field
                label="Member email"
                hint="Add an existing customer by email — the backend resolves them to their account."
              >
                <Input
                  /* eslint-disable-next-line jsx-a11y/no-autofocus -- focus the first field on open */
                  autoFocus
                  type="email"
                  value={draft.email}
                  placeholder="name@example.com"
                  // Picking a persona takes precedence, so typing an email clears any picked persona.
                  onChange={(e) => onChange({ email: e.target.value, personaId: "" })}
                />
              </Field>
              <div className="border-t border-apt-border pt-6">
                {/* The FAILURE is read first. A failed read leaves the rows null, so testing for
                    null first would leave the picker saying "Loading personas…" forever over a read
                    that has already given up. */}
                {personasError ? (
                  <ErrorText error={personasError} />
                ) : personas === null ? (
                  <p className="text-sm text-apt-text-muted">Loading personas…</p>
                ) : personas.length === 0 ? (
                  <p className="text-sm text-apt-text-muted">You have no personas to add.</p>
                ) : (
                  <Field
                    label="…or add a persona"
                    hint="Add one of your personas. It must be allowed to act for a team, or the add is rejected."
                  >
                    <Select
                      value={draft.personaId}
                      // A picked persona clears the email (they're mutually exclusive; persona wins).
                      onChange={(e) => onChange({ email: "", personaId: e.target.value })}
                    >
                      <option value="">Choose a persona…</option>
                      {personas.map((persona) => (
                        <option key={persona.id} value={persona.id}>
                          {persona.name}
                        </option>
                      ))}
                    </Select>
                  </Field>
                )}
              </div>
              <ErrorText error={formError} />
            </div>
          )}
        />
      )}
    </div>
  );
}
