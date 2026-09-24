"use client";

import { useEffect, useMemo, useState, type ReactNode } from "react";
import {
  AlignLeft,
  BookOpen,
  Brain,
  Drama,
  FolderKanban,
  IdCard,
  KeyRound,
  MessageSquare,
  Plug,
  ShieldCheck,
  SlidersHorizontal,
  Sparkles,
  Target,
  Wrench,
} from "lucide-react";
import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";
import { CRUD_TABLES, CrudDataView, useExitGuardChannel } from "@agentic-toolkit/crud";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { Field, FieldGroup, ButtonBar } from "@agenticdevelopertoolkit/ui/blocks";
import { useDirtyDraft } from "@agenticdevelopertoolkit/ui/hooks/useDirtyDraft";
import { useExitGate, type PaneExitGuard } from "@agenticdevelopertoolkit/ui/hooks/useExitGate";
import { UnsavedChangesAlert } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-alert";
import {
  StackGroupDetail,
  useRailExitGuard,
  useRecordAffordance,
  type GroupTopicItem,
} from "@agentic-toolkit/resource";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import {
  PrivacyLevelSelect,
  PRIVACY_WIRE_VALUE,
  PRIVACY_LEVEL_FROM_WIRE,
} from "@agenticdevelopertoolkit/ui/components/privacy-level-select";
import { RdidEditor } from "@agentic-toolkit/adh-ui/components/rdid-editor";
import { rdidPrefix, validateLeaf } from "@agentic-toolkit/adh-ui/rdid";
import { PersonaAvatarField } from "./PersonaAvatarField";
import { AbilitiesPanel } from "./AbilitiesPanel";
import { PermissionsPanel } from "./PermissionsPanel";
import { InterestsEditor } from "./InterestsEditor";
import { KnowledgeFacet } from "./InterestDocumentsPane";
import { DemoFacet } from "./DemoFacet";
import { ChatStatusFacet } from "./ChatStatusFacet";
import { ItemAccessPanel, workspaceSubjectsDirectory } from "@agentic-toolkit/teams";
import {
  api,
  personaBlank,
  personaToBody,
  toPersonaDraft,
  type Persona,
  type PersonaBody,
  type PersonaDraft,
  type UserService,
} from "@agentic-toolkit/data/personas";

/** A multi-field topic pane: padded + edge-to-edge (GroupTopicDetail renders
 *  panes with no inset, so the fields carry their own) and scrolls if tall. */
function TopicPane({ children }: { children: ReactNode }) {
  return <div className="flex flex-col gap-4 px-6 py-4">{children}</div>;
}

/** A topic whose whole detail pane is one labelled textarea: it fills the pane
 *  and scrolls internally (one big field per topic reads better than a cramped
 *  fixed-height box). The label stays associated with the textarea via Field, so
 *  it keeps its accessible name. */
function FullPaneField({
  label,
  hint,
  value,
  onChange,
  placeholder,
}: {
  label: string;
  hint?: string;
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
}) {
  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col px-6 py-4">
      <Field label={label} hint={hint} className="min-h-0 flex-1">
        <Textarea
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder}
          className="min-h-0 flex-1 resize-none"
        />
      </Field>
    </div>
  );
}

/** A centered notice for a facet pane that either needs a saved persona (a draft has no id/owned
 *  ecosystem to scope its knowledge, memory, tools, or permissions to — mirrors the avatar/chat
 *  "save first" gates) or a saved persona whose owned ecosystem isn't provisioned yet, OR whose
 *  host hasn't wired the facet's injected renderer (embedded views that omit it). */
function SaveFirstNotice({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col items-center justify-center p-6 text-center">
      <p className="text-sm text-apt-text-muted">{children}</p>
    </div>
  );
}

/** One labelled, resizable textarea sized for grouping SEVERAL in a scrolling pane (the Personality
 *  facet stacks Character + Voice + Examples), as opposed to FullPaneField's single pane-filling
 *  field. */
function TallTextareaField({
  label,
  hint,
  value,
  onChange,
  placeholder,
}: {
  label: string;
  hint?: string;
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
}) {
  return (
    <Field label={label} hint={hint}>
      <Textarea
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="min-h-32 resize-y"
      />
    </Field>
  );
}

// The persona's own memory rows live in persona-memory/memories (a personaId-keyed, generic-CRUD
// table). The Memory facet surfaces THIS persona's rows through the same CrudDataView the All-Data /
// Knowledge Bases browser uses — filtered to the persona and scoped to its ecosystem. (v1: this is
// the editable generic-CRUD editor, not a purpose-built read-only memory view — see phase-3b report.)
const MEMORIES_TABLE = CRUD_TABLES["persona-memory/memories"]!;

/** The Memory facet's pane: the persona's memory rows in a CrudDataView, filtered to this persona and
 *  scoped to the ecosystem it OWNS (not its scoping/home `ecosystemId` — when a persona acts as
 *  `self` it reads/writes memory under the ecosystem it owns), with its unsaved-work guard bridged
 *  into the host rail (exactly as IntegrationData does for a provider's synced-data table, via the
 *  same `useRailExitGuard` seam). A separate component so its hooks don't run inside the editor's
 *  topic-render closure. */
function PersonaMemoryPane({
  personaId,
  ownedEcosystemId,
}: {
  personaId: string;
  ownedEcosystemId: string;
}) {
  const { exitGuard, registerGuard } = useExitGuardChannel();
  useRailExitGuard(exitGuard);
  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col px-6 py-4">
      <CrudDataView
        meta={MEMORIES_TABLE}
        filter={{ personaId }}
        scopeEcosystemId={ownedEcosystemId}
        onGuardChange={registerGuard}
      />
    </div>
  );
}

const BLANK = personaBlank();

/** Build the wire body from a draft (drop display-only joins; coerce blanks to undefined). */
const toBody = personaToBody;

export interface SaveBlock {
  message: string;
  topicId: string;
}

/**
 * Why Save is blocked, or null when it is not. A located REASON rather than a boolean, because a
 * silently disabled Save is the actual bug: the old gate also required `modelPrompt`, which lives
 * in the Purpose topic, so a user editing Identity had no way to discover what was holding the
 * button down. Returning the topic id lets the caller point at the offending pane.
 *
 * `modelPrompt` is deliberately NOT required. Quick-create already produces personas with a blank
 * prompt, so refusing to save one here contradicted how the row came into existence.
 *
 * `visibility` needs no clause: it is a closed enum that always holds a value. What makes the
 * visibility popup move the button is the `dirty` term in the gate, not validation.
 */
export function saveBlockedReason(draft: PersonaDraft): SaveBlock | null {
  if (draft.name.trim() === "") return { message: "Enter a name in Identity.", topicId: "identity" };
  if (draft.slug.trim() === "") return { message: "Enter a slug in Identity.", topicId: "identity" };
  const slugError = validateLeaf(draft.slug);
  if (slugError) return { message: `Slug: ${slugError}`, topicId: "identity" };
  return null;
}

/**
 * The persona editor — a topic/detail (one stack level) whose leaf carries a Save/Cancel bar over
 * the active section's fields, for both create (`persona === null`) and edit. The caller owns the
 * list; this pane owns the draft, validation, and save, then signals back.
 *
 * Several surfaces cross a package boundary the editor itself can't reach, so the HOST injects them:
 *  - `renderChatPane` — the live try-it chat (needs the host's own chat wiring);
 *  - `renderModelDetails` — the rich model browser beside the Model select (per-model metadata and
 *    a provider re-fetch, which read/write the host's service rows);
 *  - `profileUrlFor` — the persona's public profile URL (needs the host's site-URL config);
 *  - `renderKnowledgeBases` — the Knowledge Bases browser (a separate feature package this one
 *    doesn't depend on);
 *  - `renderIntegrations` — the provider-config pane scoped to the ecosystem this persona OWNS
 *    (same @agentic-toolkit/integrations pane the Products FTD mounts for a product's ecosystem —
 *    a persona is an ecosystem too, and its integrations are reached by going into it rather than
 *    from a destination picker; see the Integrations facet below).
 * Each is optional, and omitting one degrades rather than breaks: the affordance is hidden (profile
 * URL, model details — the plain Select still picks a model) or replaced by a distinct "not
 * available in this view" notice (chat / knowledge bases / integrations) rather than the misleading
 * "save first" copy — the persona IS already saved, the view just doesn't wire it.
 */
export function PersonaEditor({
  persona,
  services,
  workspaceSlug,
  onSaved,
  onCancel,
  activeSubtab,
  onSubtabChange,
  renderChatPane,
  renderModelDetails,
  profileUrlFor,
  renderKnowledgeBases,
  renderProject,
  renderTransferOwnership,
  renderIntegrations,
}: {
  /** The persona to edit, or null to create a new one. */
  persona: Persona | null;
  /** The workspace whose principal will OWN a newly-created persona (threaded to create as
   *  `?workspace=` — see PersonasSection). Omit and the creator owns it. Saves of an existing
   *  persona are unaffected. */
  workspaceSlug?: string;
  /** The caller's services (for the service/model selects). */
  services: UserService[];
  onSaved: (saved: Persona) => void;
  onCancel: () => void;
  /** The active editor sub-tab from the URL (identity/description/…); undefined shows the first
   *  tab (Identity) with NO redirect. Meaningful only for a saved persona — a draft has no id to
   *  address, so the caller omits `onSubtabChange` while creating and sub-tabs select locally. */
  activeSubtab?: string;
  /** Route to a sub-tab (or null to clear back to the bare persona URL). When provided, the
   *  editor's sub-tab selection is URL-driven; omitted for a new draft (local selection). */
  onSubtabChange?: (subtab: string | null) => void;
  /** Renders the live try-it chat for a SAVED persona (the LLM Settings facet). Omit to show a
   *  "not available in this view" notice instead. */
  renderChatPane?: (persona: Persona) => ReactNode;
  /** Renders a richer model browser beside the Model select (the LLM Settings facet) — the one
   *  the plain `<Select>` of model names can't be: per-model context window, max output tokens,
   *  pricing, modalities and capability flags, plus a live re-fetch of the provider's model list.
   *  That view reads a service's provider metadata and writes back a refreshed service row, which
   *  is host-app territory, so it's injected the same way `renderChatPane` is. Called only when a
   *  service is selected; omit it and the facet is the bare Select. */
  renderModelDetails?: (args: {
    /** The currently selected service — the models being browsed belong to it. */
    service: UserService;
    selectedModelId: string | null;
    /** Writes the chosen model into the draft (null clears it). Does NOT save. */
    onSelect: (modelId: string | null) => void;
  }) => ReactNode;
  /** The persona's public profile URL for a given slug. Omit to hide the Public URL affordance
   *  entirely (it stays gated on `visibility === "public"` and a non-empty slug either way). */
  profileUrlFor?: (slug: string) => string;
  /** Renders the Knowledge Bases browser scoped to the persona's OWNED ecosystem (the Knowledge
   *  facet). Omit to show a "not available in this view" notice instead. */
  renderKnowledgeBases?: (scopeEcosystemId: string) => ReactNode;
  /** Renders the persona's auto-provisioned PROJECT (the Project facet — a separate feature
   *  package this one doesn't depend on, so the host injects the pane, e.g.
   *  @agentic-toolkit/projects' SubjectProjectPane). Omit to show a "not available in this
   *  view" notice instead. */
  renderProject?: (personaId: string) => ReactNode;
  /** Host-rendered "Transfer Ownership" section for the Identity topic. The workspace list and the
   *  transfer mutation live in the host; this package stays host-agnostic. Omitted ⇒ no section. */
  renderTransferOwnership?: (persona: Persona) => ReactNode;
  /** Renders the integrations pane scoped to the persona's OWNED ecosystem (the Integrations
   *  facet) — @agentic-toolkit/integrations' IntegrationsPane is a separate feature package this
   *  one doesn't depend on, so the host injects it, the same seam shape as renderKnowledgeBases.
   *  Omit to show a "not available in this view" notice instead. */
  renderIntegrations?: (ecosystemId: string) => ReactNode;
}) {
  // Derive the initial draft from the persona prop; keyed remount (per id) in the
  // parent gives each persona a fresh editor, so seeding state here is safe.
  const { draft, set, dirty, commit } = useDirtyDraft<PersonaDraft>(() =>
    persona ? toPersonaDraft(persona) : BLANK,
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const renderRecordAffordance = useRecordAffordance();
  // What a create returned, remembered locally. `commit()` deliberately leaves this editor MOUNTED
  // and re-armed after a successful save, but `persona` is a prop the parent need not refresh (it
  // may keep passing null) — so newness cannot be read from the prop alone or the second Save would
  // POST a DUPLICATE persona. Everything below asks `persisted`, never `persona`, which also lets
  // the id-gated facets (avatar, knowledge, memory, abilities…) come alive the moment it exists.
  const [created, setCreated] = useState<Persona | null>(null);
  const persisted = persona ?? created;

  const isNew = persisted === null;
  const block = saveBlockedReason(draft);
  const valid = block === null;
  const idPrefix = rdidPrefix(persisted?.id);

  const activeService = useMemo(
    () => services.find((s) => s.id === draft.serviceId) ?? null,
    [services, draft.serviceId],
  );
  // A service switch invalidates the model: clear it unless the new service still offers it.
  useEffect(() => {
    if (draft.model && activeService && !activeService.models.some((m) => m.id === draft.model)) {
      set("model", null);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [draft.serviceId]);

  // Returns whether the persona is now persisted — `false` on a blocked or failed save, read by
  // the Save/Cancel bar's onSave below (the button stays disabled while a request is in flight;
  // `error` carries why a save didn't land). Not part of the exit-guard contract: PaneExitGuard
  // has no `save()`, so nothing outside this editor reads the return value.
  async function save(): Promise<boolean> {
    if (!valid) return false;
    setSaving(true);
    setError(null);
    try {
      const body = toBody(draft);
      // The workspace scope rides every write (workspaceQuery no-ops when absent):
      // update under an org workspace needs it so a member can save personas OTHER
      // members created for the org (the item ownership scope replaces the creator pin).
      // Update targets the DRAFT's id, not the prop's: `commit()` re-baselines it from the server's
      // response, so it tracks an id the rdid cascade rewrote where a captured prop would not.
      const saved = persisted
        ? await api.personas.update(draft.id, body, { workspace: workspaceSlug })
        : await api.personas.create(body, { workspace: workspaceSlug });
      // The server normalises (slug casing, trimming) and — after the rdid cascade — may return a
      // different id than we sent. Adopt what it actually stored, so `dirty` measures the draft
      // against the saved truth rather than against what we optimistically hoped.
      commit(toPersonaDraft(saved));
      if (!persisted) setCreated(saved);
      onSaved(saved);
      return true;
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "personas", step: "save" });
      setError(err instanceof Error ? err.message : "Failed to save persona.");
      return false;
    } finally {
      setSaving(false);
    }
  }

  // The persona FORM's unsaved-work guard — the one PersonaMemoryPane's (above) does NOT cover.
  // Publishing it dirty-gated is what reaches every exit the editor does not own: the rail's row
  // switch and breadcrumb (through the host's HTD exit gate) and reload / tab close / link click /
  // Back (through the host's `<UnsavedChangesGuard when={guards.size > 0} />`, which stays false
  // until something registers). Same shape as ResearchPane's.
  //
  // Memoized on `dirty` alone (its only dependency once `save` dropped off the interface): this is
  // `useExitGate`'s sole argument below, and its `attemptExit` `useCallback` depends on THIS
  // object's identity, not its contents — an unmemoized literal would give `attemptExit` a fresh
  // identity every render despite nothing observable changing.
  const exitGuard = useMemo<PaneExitGuard | null>(
    () => (dirty ? { isDirty: () => dirty } : null),
    [dirty],
  );
  useRailExitGuard(exitGuard);
  // ...and the one exit the editor DOES own: its Save/Cancel bar is rendered in the leaf, so Cancel
  // never passes through the host's gate. The shared hook rather than a local copy of the
  // hold-the-action dance, so this prompt cannot drift from every other block's.
  const { attemptExit, exitAlertProps } = useExitGate(exitGuard);

  // The editor is a topic/detail published into the one merged stack, framing the persona as its
  // five facets — Personality (character + voice + examples), Purpose (its prompt), Knowledge, Memory,
  // Abilities — plus context-scoped Permissions, bracketed by the structural sections that don't map
  // to a facet: Identity + Description on top, LLM Settings (with its live chat) at the bottom. The
  // facet panes that act on a real persona (Knowledge / Memory / Abilities / Permissions) are gated
  // behind the first save. The Save/Cancel bar lives IN the leaf (above the active section).
  const topics: GroupTopicItem[] = [
    {
      id: "identity",
      label: "Identity",
      icon: <IdCard size={16} aria-hidden />,
      blocked: block?.topicId === "identity",
      render: () => (
        <TopicPane>
          <FieldGroup title="Identity">
            <Field label="Name">
              <Input value={draft.name} onChange={(e) => set("name", e.target.value)} placeholder="Bob" />
            </Field>
            <RdidEditor
              label="Slug"
              prefix={idPrefix}
              value={draft.slug}
              placeholder="bob"
              hint={
                idPrefix
                  ? "Only the name is editable — the inherited scope is fixed. The persona's public URL."
                  : "URL-safe id (lowercase, digits, hyphens). The persona's public URL."
              }
              error={draft.slug ? validateLeaf(draft.slug) : undefined}
              onChange={(leaf) => set("slug", leaf)}
            />
            <Field label="Avatar" hint="Shown on the persona's public profile.">
              {isNew ? (
                // The upload owns the attachment by persona id (ownerType='persona',
                // ownerId=persona.id), and the public avatar read is scoped to that —
                // so an avatar can only be attached once the persona has a real id.
                // A draft has none, so gate it behind the first save (like chat).
                <p className="text-sm text-apt-text-muted">
                  Save this persona first to add an avatar.
                </p>
              ) : (
                <PersonaAvatarField
                  personaId={persisted.id}
                  value={draft.avatarAttachmentId}
                  onChange={(id) => set("avatarAttachmentId", id)}
                />
              )}
            </Field>
            <Field label="Visibility">
              <PrivacyLevelSelect
                value={PRIVACY_LEVEL_FROM_WIRE(draft.visibility)}
                ariaLabel="Persona visibility"
                onChange={(next) => set("visibility", PRIVACY_WIRE_VALUE[next])}
              />
            </Field>
            {/* Public personas have a live profile page; surface the full URL so
                the owner can open/share it. Opens in a new tab. Hidden entirely
                when the host doesn't inject a profile-URL resolver. */}
            {profileUrlFor && draft.visibility === "public" && draft.slug.trim() !== "" && (
              <div className="flex flex-col items-start gap-1.5">
                <span className="font-mono text-[0.7rem] uppercase tracking-wider text-apt-text-muted">
                  Public URL
                </span>
                <a
                  href={profileUrlFor(draft.slug.trim())}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="break-all font-mono text-sm text-apt-gold underline-offset-2 outline-none hover:underline focus-visible:ring-2 focus-visible:ring-apt-gold/40"
                >
                  {profileUrlFor(draft.slug.trim())}
                </a>
              </div>
            )}
          </FieldGroup>
          {persisted && renderTransferOwnership && renderTransferOwnership(persisted)}
        </TopicPane>
      ),
    },
    {
      id: "description",
      label: "Description",
      icon: <AlignLeft size={16} aria-hidden />,
      render: () => (
        <FullPaneField
          label="Description"
          value={draft.description ?? ""}
          onChange={(v) => set("description", v || null)}
          placeholder="A one-line summary of this persona."
        />
      ),
    },
    {
      id: "personality",
      label: "Personality",
      icon: <Drama size={16} aria-hidden />,
      // Facet 1 — how the persona expresses itself: its Character (who it is) and Voice (how it
      // speaks), grouped with the few-shot Examples that demonstrate both. Three fields in one
      // scrolling pane, so the whole personality reads as a single facet.
      render: () => (
        <div className="flex min-h-0 min-w-0 flex-1 flex-col gap-4 overflow-y-auto px-6 py-4">
          <TallTextareaField
            label="Character"
            hint="Personality, quirks, values."
            value={draft.character ?? ""}
            onChange={(v) => set("character", v || null)}
            placeholder="Personality, quirks, values."
          />
          <TallTextareaField
            label="Voice"
            hint="How the persona speaks."
            value={draft.voice ?? ""}
            onChange={(v) => set("voice", v || null)}
            placeholder="How the persona speaks."
          />
          <TallTextareaField
            label="Examples"
            hint="Example exchanges (few-shot) that demonstrate its character and voice."
            value={draft.examples ?? ""}
            onChange={(v) => set("examples", v || null)}
            placeholder="Example exchanges."
          />
          {/* Interests are a CHILD table with their own save, so they sit below the three draft
              fields rather than joining them — same facet (this is where an author writes the
              persona's personality), different lifecycle. `persisted` is null for an unsaved draft. */}
          <InterestsEditor personaId={persisted?.id ?? null} />
        </div>
      ),
    },
    {
      id: "purpose",
      label: "Purpose",
      icon: <Target size={16} aria-hidden />,
      // Facet 2 — the persona's purpose IS its `modelPrompt`: the system prompt that defines what it
      // is for (required). Alongside the editor, an "API" button opens a live, authed try-it panel for
      // GET /persona/personas/{id} (id prefilled), only once the persona exists.
      render: () => (
        <div className="flex min-h-0 min-w-0 flex-1 flex-col">
          {persisted && (
            <div className="px-6 pt-4">
              <span className="text-xs text-apt-text-muted">
                Stored as the <code className="font-mono">modelPrompt</code> field on this persona.
              </span>
            </div>
          )}
          <FullPaneField
            label="Purpose"
            hint="The system prompt that defines what this persona is for — required."
            value={draft.modelPrompt}
            onChange={(v) => set("modelPrompt", v)}
            placeholder="You are Bob, an expert at naming dogs…"
          />
        </div>
      ),
    },
    {
      id: "project",
      label: "Project",
      icon: <FolderKanban size={16} aria-hidden />,
      description: "The persona's own project — plan and track its work.",
      // The persona's auto-provisioned PROJECT (subject-linked at create / by the deploy
      // backfill). The projects feature package is a sibling this package doesn't depend
      // on, so its pane is host-injected (renderProject) — same seam as Knowledge above.
      render: () => {
        if (!persisted) {
          return <SaveFirstNotice>Save this persona first to open its project.</SaveFirstNotice>;
        }
        if (!renderProject) {
          return <SaveFirstNotice>The project isn't available in this view.</SaveFirstNotice>;
        }
        return renderProject(persisted.id);
      },
    },
    {
      id: "knowledge",
      label: "Knowledge",
      icon: <BookOpen size={16} aria-hidden />,
      // Facet 3 — the persona's knowledge: the Knowledge Bases surface (host-injected, scoped to
      // the ecosystem this persona OWNS) plus one tab per special interest, whose research corpus
      // lives in the OWNER's realm (`corpusEcosystemId`) instead. Two different ecosystems, which
      // is why they are sibling tabs rather than one merged pane. A draft has no id, so gate the
      // whole facet behind the first save; the per-pane "not provisioned yet" cases are handled
      // inside KnowledgeFacet.
      render: () => {
        if (!persisted) {
          return <SaveFirstNotice>Save this persona first to manage its knowledge bases.</SaveFirstNotice>;
        }
        return <KnowledgeFacet persona={persisted} renderKnowledgeBases={renderKnowledgeBases} />;
      },
    },
    {
      id: "memory",
      label: "Memory",
      icon: <Brain size={16} aria-hidden />,
      // Facet 4 — this persona's own memory rows (persona-memory/memories), filtered to it and scoped
      // to the ecosystem it OWNS (see PersonaMemoryPane's doc comment). Gated behind the first save
      // (a draft has no id), and again behind the owned ecosystem existing (see Knowledge above).
      render: () => {
        if (!persisted) {
          return <SaveFirstNotice>Save this persona first to view its memory.</SaveFirstNotice>;
        }
        if (!persisted.ownedEcosystemId) {
          return <SaveFirstNotice>This persona's memory isn't available yet.</SaveFirstNotice>;
        }
        return (
          <PersonaMemoryPane personaId={persisted.id} ownedEcosystemId={persisted.ownedEcosystemId} />
        );
      },
    },
    {
      id: "integrations",
      label: "Integrations",
      icon: <Plug size={16} aria-hidden />,
      // This persona's own provider connections — GitHub, Stripe, Gmail… — scoped to the
      // ecosystem it OWNS. A persona is an ecosystem with its own features, so its integrations
      // are reached by going INTO it (this facet) rather than from the workspace-level
      // Integrations destination picker, which deliberately dropped personas (see
      // agenticdeveloperhub's IntegrationsRoute doc comment). Host-injected because
      // @agentic-toolkit/integrations is a sibling package this one doesn't depend on — same seam
      // shape as Knowledge/Memory above. Gated behind the first save and the owned ecosystem
      // existing, same as Memory.
      render: () => {
        if (!persisted) {
          return <SaveFirstNotice>Save this persona first to manage its integrations.</SaveFirstNotice>;
        }
        if (!persisted.ownedEcosystemId) {
          return <SaveFirstNotice>This persona's integrations aren't available yet.</SaveFirstNotice>;
        }
        if (!renderIntegrations) {
          return <SaveFirstNotice>Integrations aren't available in this view.</SaveFirstNotice>;
        }
        return renderIntegrations(persisted.ownedEcosystemId);
      },
    },
    {
      id: "abilities",
      label: "Abilities",
      icon: <Wrench size={16} aria-hidden />,
      // Facet 5 — what tools this persona HAS: grant/revoke + per-tool autonomy, against its real id.
      // Gated behind the first save.
      render: () =>
        persisted ? (
          <div className="flex min-h-0 min-w-0 flex-1 flex-col gap-4 overflow-y-auto px-6 py-4">
            <AbilitiesPanel personaId={persisted.id} />
          </div>
        ) : (
          <SaveFirstNotice>Save this persona first to grant it tools.</SaveFirstNotice>
        ),
    },
    {
      id: "permissions",
      label: "Permissions",
      icon: <ShieldCheck size={16} aria-hidden />,
      // Context-scoped Permissions — WHERE / AS-WHAT this persona may act (its may_act grants) plus
      // its pending human-decision queue. Gated behind the first save.
      render: () =>
        persisted ? (
          <div className="flex min-h-0 min-w-0 flex-1 flex-col gap-4 overflow-y-auto px-6 py-4">
            <PermissionsPanel personaId={persisted.id} />
          </div>
        ) : (
          <SaveFirstNotice>Save this persona first to configure its permissions.</SaveFirstNotice>
        ),
    },
    // WHO may reach this persona — the per-item share panel (restriction mode + item-scoped
    // role assignments + the effective-permission explainer; docs/workspace-roles-permissions.md).
    // Distinct from Permissions above, which is what the persona itself may DO.
    //
    // Item access is a WORKSPACE concept, so the topic is absent entirely outside one (the
    // registry mounts this editor with no workspaceSlug) rather than listed and then explaining
    // it can't work here: a topic that never has anything to show is noise, not degradation.
    // Inside a workspace it stays listed and gated behind the first save like its neighbours,
    // because there the answer really is "not yet".
    ...(workspaceSlug
      ? [
          {
            id: "access",
            label: "Access",
            icon: <KeyRound size={16} aria-hidden />,
            render: () =>
              persisted ? (
                <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto">
                  <ItemAccessPanel
                    workspaceSlug={workspaceSlug}
                    feature="personas"
                    itemId={persisted.id}
                    itemLabel={persisted.name || persisted.slug}
                    subjectsDirectory={workspaceSubjectsDirectory}
                  />
                </div>
              ) : (
                <SaveFirstNotice>Save this persona first to manage who can access it.</SaveFirstNotice>
              ),
          },
        ]
      : []),
    {
      id: "demo",
      label: "Demo Chat",
      icon: <MessageSquare size={16} aria-hidden />,
      description:
        "A scripted conversation anyone can hold with this persona — no LLM service required.",
      render: () => (
        <DemoFacet value={draft.cannedChat} onChange={(v) => set("cannedChat", v)} />
      ),
    },
    {
      id: "chatStatus",
      label: "Chat Status",
      icon: <Sparkles size={16} aria-hidden />,
      description:
        "The words and the animated glyph shown while this persona is working.",
      render: () => (
        <ChatStatusFacet value={draft.chatStatus} onChange={(v) => set("chatStatus", v)} />
      ),
    },
    {
      id: "llm",
      label: "LLM Settings",
      icon: <SlidersHorizontal size={16} aria-hidden />,
      // A structural section (not a facet): the Settings card (service + model) on top, with a live
      // chat against that configuration below it — so you can pick a model and try it in one place.
      // The chat pane needs the host's own chat wiring (a package this one can't depend on), so it's
      // host-injected; a saved persona whose host omits it gets a distinct notice from the "save
      // first" copy shown to an unsaved draft.
      render: () => (
        <div className="flex min-h-0 min-w-0 flex-1 flex-col gap-4 px-6 py-4">
          <FieldGroup title="Settings">
            <Field label="Service" hint="The persona-service this persona runs on.">
              <Select
                value={draft.serviceId ?? ""}
                onChange={(e) => set("serviceId", e.target.value || null)}
              >
                <option value="">No service</option>
                {services.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Model">
              {/* Select grows, the injected details affordance keeps its natural width. The
                  sizing lives on this wrapper, not on Select's `className` — that lands on the
                  inner <select>, while the flex CHILD here is Select's own `relative` chevron
                  wrapper, which would stay content-sized. */}
              <div className="flex min-w-0 items-center gap-2">
                <div className="min-w-0 flex-1">
                  <Select
                    value={draft.model ?? ""}
                    onChange={(e) => set("model", e.target.value || null)}
                    disabled={!activeService || activeService.models.length === 0}
                  >
                    <option value="">
                      {activeService ? "No model selected" : "Pick a service first"}
                    </option>
                    {activeService?.models.map((m) => (
                      <option key={m.id} value={m.id}>
                        {m.displayName ?? m.id}
                      </option>
                    ))}
                  </Select>
                </div>
                {activeService &&
                  renderModelDetails?.({
                    service: activeService,
                    selectedModelId: draft.model ?? null,
                    onSelect: (modelId) => set("model", modelId),
                  })}
              </div>
            </Field>
          </FieldGroup>
          {persisted ? (
            renderChatPane ? (
              renderChatPane(persisted)
            ) : (
              <div className="flex min-h-0 min-w-0 flex-1 flex-col items-center justify-center p-6 text-center">
                <p className="text-sm text-apt-text-muted">Chat isn't available in this view.</p>
              </div>
            )
          ) : (
            <div className="flex min-h-0 min-w-0 flex-1 flex-col items-center justify-center p-6 text-center">
              <p className="text-sm text-apt-text-muted">Save this persona to start chatting with it.</p>
            </div>
          )}
        </div>
      ),
    },
  ];

  // The Save/Cancel bar sits at the top of the LEAF (the active section's pane), not in a bar above
  // the whole stack. Delete is intentionally absent here.
  const leafHeader = (
    <>
      <ButtonBar
        actions={{
          onCreate: () => {},
          onCancel: () => attemptExit(onCancel),
          canCancel: true,
          onSave: () => void save(),
          canSave: dirty && valid,
          saving,
        }}
        showCreate={false}
        showDelete={false}
        leading={
          block && (dirty || isNew) ? (
            <span className="text-xs text-apt-text-muted" role="status">
              {block.message}
            </span>
          ) : undefined
        }
      />
      <ErrorText error={error} className="px-6 pt-2" />
      {/* The persona's API, on every facet: the item read once saved, the create POST while new. */}
      <div className="flex justify-end px-6 pt-2">
        {persisted
          ? renderRecordAffordance?.({
              method: "GET",
              path: "/persona/personas/{id}",
              pathValues: { id: persisted.id },
              title: "Persona API",
            })
          : renderRecordAffordance?.({
              method: "POST",
              path: "/persona/personas",
              pathValues: {},
              title: "Create persona API",
            })}
      </div>
    </>
  );

  return (
    <>
    <StackGroupDetail
      levelId="persona-topics"
      title={isNew ? "New persona" : draft.name || "Persona"}
      items={topics}
      leafHeader={leafHeader}
      // URL-drive the sub-tab only for a saved persona (a draft has no id to address, so it selects
      // sub-tabs in local state). With no sub-tab in the URL nothing opens — the bare
      // /<slug>/personas/<id> URL shows the topics unselected (never auto-select a topic).
      urlSelection={
        onSubtabChange
          ? { selectedId: activeSubtab ?? null, onSelect: onSubtabChange }
          : undefined
      }
    />
      {/* The platform's one prompt, for the Cancel gate above. StackGroupDetail publishes a level
          rather than wrapping a subtree, so this is a sibling, not a child. */}
      <UnsavedChangesAlert {...exitAlertProps} />
    </>
  );
}
