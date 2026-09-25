"use client";

import { useEffect, useState, type ReactNode } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { UserCircle } from "lucide-react";
import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";
import { readTokenSubject, revalidateResources } from "@agentic-toolkit/data";
import { HierarchicalDetailView, type TopicDetailItem, type TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Textarea } from "@agenticdevelopertoolkit/ui/components/textarea";
import { useDualModeSelection } from "@agenticdevelopertoolkit/ui/hooks/useDualModeSelection";
import { slugify } from "@agenticdevelopertoolkit/ui/lib/slug";
import { validateLeaf } from "@agentic-toolkit/adh-ui/rdid";
import {
  StackLevels,
  useRailHost,
  CreateResourceDialog,
} from "@agentic-toolkit/resource";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { api, type Persona } from "@agentic-toolkit/data/personas";
import { PersonaEditor } from "./PersonaEditor";
import { PERSONA_SERVICES_CACHE_KEY, useUserServices } from "./useUserServices";

/**
 * The Personas feature: the persona list as a stack LEVEL and the editor as the leaf (the frame's
 * select hint while nothing is open). Under a rail host it PUBLISHES its level into the host's
 * merged stack (via `useRailHost`) and renders only the leaf; standalone it renders its own
 * HierarchicalTopicDetail. Either way "New Persona" is the persona list's own toolbar `+`, beside its
 * search; the breadcrumb names the open persona (from the level).
 *
 * DUAL SELECTION MODE (mirrors useMasterDetailForm.urlSelection): pass `urlSelection` and the open
 * persona + editor sub-tab are URL-driven + deep-linkable — a host's top-level Personas route wires
 * this (see `PersonasFeature`, or the hub's `PersonasGroupRoute`). Omit it — as an embedded launcher
 * does — and selection is internal state, so opening a persona happens IN PLACE without navigating
 * out of the surrounding surface.
 *
 * Three facets the editor renders cross a package boundary this feature can't reach on its own, so
 * a host injects them (see {@link PersonaEditor} for the exact fallback behavior when omitted):
 * `renderChatPane`, `profileUrlFor`, and `renderKnowledgeBases`.
 */
export function PersonasSection({
  urlSelection,
  workspaceSlug,
  renderChatPane,
  profileUrlFor,
  renderKnowledgeBases,
  renderProject,
  renderTransferOwnership,
  renderIntegrations,
}: {
  /** The workspace whose personas this section shows. Resolved server-side to the workspace's
   *  OWNING principal (`?workspace=`): the list holds only personas that principal owns, and a
   *  persona created here is owned BY that principal (an org workspace's persona is org-owned).
   *  Omit for the caller's own creator-scoped personas (the pre-workspace behavior). */
  workspaceSlug?: string;
  urlSelection?: {
    /** The open persona's id, from the first URL path segment (`/<slug>/personas/<id>`). */
    personaId?: string;
    /** The active editor sub-tab, from the second segment (`/<slug>/personas/<id>/<subtab>`). */
    subtab?: string;
    /** Route to a persona (null clears back to the list). */
    onSelectPersona: (id: string | null) => void;
    /** Route to an editor sub-tab (null clears to the bare persona URL). Optional: a caller that
     *  URL-drives ONLY the open persona (e.g. a grouped ecosystem member ceding just the entity
     *  segment) omits it, and the editor keeps its own internal sub-tab selection. */
    onSelectSubtab?: (subtab: string | null) => void;
  };
  /** Renders the live try-it chat for a saved persona. See {@link PersonaEditor}. */
  renderChatPane?: (persona: Persona) => ReactNode;
  /** The persona's public profile URL for a given slug — threaded to the editor's Identity
   *  facet. See {@link PersonaEditor}. */
  profileUrlFor?: (slug: string) => string;
  /** Renders the Knowledge Bases browser scoped to a persona's owned ecosystem. See
   *  {@link PersonaEditor}. */
  renderKnowledgeBases?: (scopeEcosystemId: string) => ReactNode;
  /** Renders a persona's auto-provisioned project (the Project facet). See
   *  {@link PersonaEditor}. */
  renderProject?: (personaId: string) => ReactNode;
  /** Host-rendered "Transfer Ownership" section. See {@link PersonaEditor}. */
  renderTransferOwnership?: (persona: Persona) => ReactNode;
  /** Renders the integrations pane scoped to a persona's owned ecosystem (the Integrations
   *  facet). See {@link PersonaEditor}. */
  renderIntegrations?: (ecosystemId: string) => ReactNode;
}) {
  // Data rides the toolkit's shared react-query cache, NOT local state: Next remounts the page
  // subtree on every param navigation, so local state would restart from null on each persona/topic
  // click and the whole list "blinks" through Loading…. The cache survives the remount, so a
  // reselect renders instantly; invalidation (reload, below) still refreshes after writes.
  //
  // Keys carry the signed-in principal (the access token's `sub`, read at render): the cache
  // outlives an identity change (nothing clears the shared QueryClient on auth swap — e.g.
  // tokens replaced by another tab), so an unscoped key could serve the PREVIOUS account's
  // personas as "fresh" on the next remount. Same tenant scoping useResourceList applies to
  // its module cache.
  const tenant = readTokenSubject();
  const queryClient = useQueryClient();
  const personasQuery = useQuery({
    queryKey: ["personas", tenant, workspaceSlug ?? null],
    queryFn: () => api.personas.list({ workspace: workspaceSlug }),
  });
  // The services ride the SHARED hook, not a second `useQuery` of their own: the Services pane
  // reads the same list, and two keys for one list meant two requests and two invalidations that
  // never reached each other — a service created over there stayed missing from this editor's
  // picker. `useUserServices` reports its own failures, hence no report for them below.
  const { items: serviceRows, error: servicesError } = useUserServices();
  const services = serviceRows ?? [];
  // Surface load failures once settled (after retry), matching the old catch-and-report.
  const loadError = personasQuery.error ?? null;
  useEffect(() => {
    if (loadError) reportUnexpectedAuthError(loadError, { feature: "personas", step: "list" });
  }, [loadError]);
  const error = loadError
    ? loadError instanceof Error
      ? loadError.message
      : "Failed to load personas."
    : servicesError;
  // Creating a persona is a MODAL over the stack, never a blank editor leaf (HTD recipe
  // `must-create-in-modal`): the persona list's toolbar `+` ("New Persona") opens it, and on save
  // the created persona is selected so its full editor (personality, purpose, abilities, …) opens.
  const [newOpen, setNewOpen] = useState(false);
  // Dual-mode selection: URL-driven (deep-linkable) when `urlSelection` is passed, else internal
  // state (the embedded /home launcher / ecosystem rail).
  const { selectedId: openPersonaId, select } = useDualModeSelection(
    urlSelection && {
      selectedId: urlSelection.personaId ?? null,
      onSelect: urlSelection.onSelectPersona,
    },
  );

  // Open a persona (or null to close): URL-driven callers navigate, embedded callers set local state.
  const selectPersona = (id: string | null) => {
    select(id);
  };

  // After a write: invalidate EVERY personas variant (all workspace scopes — a create/save can
  // affect other workspaces' lists too) plus the services list; active queries refetch immediately.
  // The services live in the shared resource cache, which is keyed `["resource-list", tenant, key]`
  // — a bare `invalidateQueries(["persona-services"])` would match nothing there.
  const reload = () => {
    void queryClient.invalidateQueries({ queryKey: ["personas"] });
    revalidateResources((k) => k === PERSONA_SERVICES_CACHE_KEY);
  };

  const rows = personasQuery.data ?? [];
  const items: TopicDetailItem[] = rows.map((p) => ({
    id: p.id,
    label: p.name,
    sublabel: p.slug,
    icon: <UserCircle size={16} aria-hidden />,
  }));

  // The open persona: the selected id resolved against the loaded rows. An unknown/deleted id (or
  // none) is "nothing open" → the select hint (fail-fast, never a blank screen).
  const openPersona = openPersonaId ? rows.find((p) => p.id === openPersonaId) ?? null : null;
  const levels: TopicLevel[] = [
    {
      id: "personas",
      title: "Personas",
      items,
      selectedId: openPersona?.id ?? null,
      onSelect: (id) => selectPersona(id),
      onClear: () => selectPersona(null),
      emptyLabel: "No personas yet.",
      // Create and search live on the list they act on — its toolbar — since the page-wide home bar
      // they used to sit in was removed as clunky (Mike, 2026-09-24). UNCONDITIONAL, as the bar's
      // button was: an empty list is exactly when the first create matters most.
      onNew: () => setNewOpen(true),
      newLabel: "New Persona",
      newActive: newOpen,
      search: { placeholder: "Search personas" },
      // The unselected pane is the frame's select hint and nothing else (docs/ui/fleet-ui-audit.md
      // §1.5) — the rail beside it already lists every persona.
      itemNoun: "persona",
      // The load failure has to ride INSIDE the hint. The frontier overview hides the pane's
      // children outright (`display: none`), so the `<ErrorText>` below is only readable while
      // the list is empty — and a personas list that loaded while the SERVICES list failed is
      // non-empty, which would swallow that error silently.
      overviewHelp: error ? <ErrorText error={error} /> : undefined,
    },
  ];

  // DUAL MODE: under a rail host, PUBLISH the persona level into the host's merged stack (its
  // selected row becomes the breadcrumb tail — Acme ▸ Personas ▸ Bob); standalone, render an own HTD.
  const railHost = useRailHost();

  const content =
    personasQuery.isPending ? (
      <p className="p-6 text-sm text-apt-text-muted">Loading…</p>
    ) : openPersona ? (
      <PersonaEditor
        key={openPersona.id}
        persona={openPersona}
        services={services}
        workspaceSlug={workspaceSlug}
        // Sub-tabs are URL-driven + deep-linkable only when this section is URL-driven; embedded,
        // the editor keeps its own internal tab selection (opening unselected), unchanged.
        activeSubtab={urlSelection?.subtab}
        onSubtabChange={urlSelection?.onSelectSubtab}
        onSaved={() => reload()}
        onCancel={() => selectPersona(null)}
        renderChatPane={renderChatPane}
        profileUrlFor={profileUrlFor}
        renderKnowledgeBases={renderKnowledgeBases}
        renderProject={renderProject}
        renderTransferOwnership={renderTransferOwnership}
        renderIntegrations={renderIntegrations}
      />
    ) : (
      // Nothing open: the frame's select hint owns this pane. It only yields to these children
      // when the list is EMPTY — which is exactly when a load failure has to be readable.
      <ErrorText error={error} className="px-6 pt-4" />
    );

  // Create is a scoped modal (HTD recipe `must-create-in-modal`): Name + Slug identify the persona;
  // Description and Prompt are optional here and — like everything else (personality, avatar,
  // abilities, permissions, and the model it runs on) — can be filled in the full editor that opens
  // once the created persona is selected. `model` is a required column with no default, so create
  // sends an empty string (as it does for the prompt): the persona exists immediately and the editor
  // guides completing it.
  const newDialog = newOpen ? (
    <CreateResourceDialog<
      { name: string; slug: string; description: string; modelPrompt: string },
      Persona
    >
      ariaLabel="New persona"
      heading="New persona"
      blank={() => ({ name: "", slug: "", description: "", modelPrompt: "" })}
      validate={(d) =>
        !d.name.trim()
          ? "A name is required."
          : !d.slug.trim()
            ? "A slug is required."
            : validateLeaf(d.slug) ?? null
      }
      saveEnabled={(d) =>
        d.name.trim() !== "" && d.slug.trim() !== "" && validateLeaf(d.slug) === null
      }
      create={(d) =>
        api.personas.create(
          {
            name: d.name.trim(),
            slug: d.slug.trim(),
            description: d.description.trim() || undefined,
            modelPrompt: d.modelPrompt,
            // `model` is a required (NOT NULL) column with no default and no field in this quick
            // modal — send an empty string so the create validates; the real model is chosen later
            // in the editor's LLM Settings.
            model: "",
            visibility: "private",
          },
          { workspace: workspaceSlug },
        )
      }
      onClose={() => setNewOpen(false)}
      onCreated={(saved) => {
        setNewOpen(false);
        selectPersona(saved.id);
        reload();
      }}
      renderForm={(draft, onChange, error) => (
        <Card>
          <CardContent className="grid grid-cols-[max-content_1fr] items-center gap-x-3 gap-y-5">
            <Label htmlFor="new-persona-name" className="justify-self-end">
              Name:
            </Label>
            <Input
              id="new-persona-name"
              /* eslint-disable-next-line jsx-a11y/no-autofocus -- focus the first field on open */
              autoFocus
              value={draft.name}
              placeholder="Bob"
              onChange={(e) => {
                const name = e.target.value;
                // Keep the slug synced to the name until the user hand-edits it (breaking the
                // equality), after which name edits leave their chosen slug alone.
                const keepInSync = draft.slug === "" || draft.slug === slugify(draft.name);
                onChange({ ...draft, name, slug: keepInSync ? slugify(name) : draft.slug });
              }}
            />

            <Label htmlFor="new-persona-slug" className="justify-self-end">
              Slug:
            </Label>
            <Input
              id="new-persona-slug"
              value={draft.slug}
              placeholder="bob"
              onChange={(e) => onChange({ ...draft, slug: e.target.value.toLowerCase() })}
            />
            <div className="col-start-2 flex flex-col gap-1">
              <span className="text-xs text-apt-text-muted">
                URL-safe id (lowercase, digits, hyphens). The persona&apos;s public URL.
              </span>
              {draft.slug && validateLeaf(draft.slug) && (
                <span className="text-xs text-apt-red">{validateLeaf(draft.slug)}</span>
              )}
            </div>

            <div className="col-span-2 flex flex-col gap-2">
              <Label htmlFor="new-persona-description">Description:</Label>
              <Textarea
                id="new-persona-description"
                rows={2}
                placeholder="A one-line summary of this persona."
                value={draft.description}
                onChange={(e) => onChange({ ...draft, description: e.target.value })}
              />
            </div>

            <div className="col-span-2 flex flex-col gap-2">
              <Label htmlFor="new-persona-prompt">Prompt:</Label>
              <Textarea
                id="new-persona-prompt"
                rows={4}
                placeholder="You are Bob, an expert at naming dogs…"
                value={draft.modelPrompt}
                onChange={(e) => onChange({ ...draft, modelPrompt: e.target.value })}
              />
            </div>

            <p className="col-span-2 text-sm text-apt-text-muted">
              Description and prompt are optional — you can add them later.
            </p>

            <div className="col-span-2">
              <ErrorText error={error} />
            </div>
          </CardContent>
        </Card>
      )}
    />
  ) : null;

  // Under a rail host: PUBLISH the persona level (StackLevels advances the depth so the editor's
  // topics land after it) and render the leaf. Standalone: own HTD. Create rides the level, so both
  // branches carry it.
  if (railHost)
    return (
      <>
        <StackLevels levels={levels}>{content}</StackLevels>
        {newDialog}
      </>
    );
  return (
    <>
      <HierarchicalDetailView levels={levels} showBreadcrumb={false}>
        {content}
      </HierarchicalDetailView>
      {newDialog}
    </>
  );
}
