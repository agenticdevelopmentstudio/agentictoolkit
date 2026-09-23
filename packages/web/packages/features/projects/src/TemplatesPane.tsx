"use client";

import { useCallback, useState, type ReactElement } from "react";
import { FileStack } from "lucide-react";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { useResourceList } from "@agentic-toolkit/data";
import {
  cardCountOf,
  projectTemplatesApi,
  type Template,
} from "@agentic-toolkit/data/projects";
import {
  CreateResourceDialog,
  FeatureTitle,
  MasterDetailLeaf,
  useMasterDetailForm,
  useMasterDetailLevel,
  useRecordAffordance,
  type TopicLeaf,
} from "@agentic-toolkit/resource";
import {
  TemplateDetail,
  templateBlank,
  templateDiffers,
  templateNormalize,
  templateToInput,
  templateToPatch,
  templateValidate,
  type TemplateDraft,
} from "./TemplateDetail";

/**
 * TEMPLATES — the shapes a workspace stamps out repeatedly, as a master/detail topic.
 *
 * Reached through a project like Iterations and Programs, and like them a template is NOT the
 * project's: it belongs to the WORKSPACE. That is not a filing decision, it is the point — a
 * template pinned to one board could only ever rebuild that board, and the shapes a team repeats
 * are exactly the ones they repeat ACROSS boards. So nothing here filters to the board you arrived
 * through.
 *
 * TWO KINDS IN ONE LIST. A card template makes a card and its checklist on a board that already
 * exists; a board template makes the board. They share a list because they are one verb ("make the
 * usual thing") with two objects, and a person deciding which they want has to see both. The rail
 * row says which is which, since the kinds behave completely differently once chosen.
 *
 * WHERE THEY ARE USED, rather than authored: a card template is offered in the "New work item"
 * dialog on any board, and a board template in "New project". This pane is the library — creating
 * from one happens where the thing is created.
 *
 * Built on the shared master/detail substrate, so it inherits the rail level, the deep-linkable
 * selection, the dirty-draft guard and the create-as-modal that every converted pane has.
 */

/* ── The rail row's second line ───────────────────────────────────────────── */

/** What a template makes, in one phrase — the answer the row exists to give, because choosing the
 *  wrong kind is the one mistake this list can cause. A card template also says how many cards it
 *  writes, which is the number that decides whether it is the one you meant. */
export function templateSublabel(t: Template): string {
  if (t.kind === "project") return "A board";
  const n = cardCountOf(t);
  return n === 1 ? "A card" : `A card + ${n - 1} step${n === 2 ? "" : "s"}`;
}

/* ── The pane ─────────────────────────────────────────────────────────────── */

export function TemplatesPane({
  title,
  leaf,
  workspaceSlug,
}: {
  title: string;
  /** The deep-linkable selection — which template is open (`…/templates/<id>`). */
  leaf: TopicLeaf;
  /** The workspace whose templates these are. Absent, the API answers with the caller's own reach,
   *  exactly as the project, iteration and program lists do. */
  workspaceSlug?: string;
}): ReactElement {
  const renderRecordAffordance = useRecordAffordance();
  const [newOpen, setNewOpen] = useState(false);

  // The SAME cache key the create dialogs read their pickers from, so a template saved here is
  // what "New work item" offers on the next mount rather than a stale copy.
  const load = useCallback(
    () => projectTemplatesApi.list({ workspace: workspaceSlug }),
    [workspaceSlug],
  );
  const {
    items: templates,
    reload,
    error: loadError,
    isFetching,
  } = useResourceList<Template>(`workspace:${workspaceSlug ?? ""}:templates`, load);

  const ws = { workspace: workspaceSlug };
  const form = useMasterDetailForm<Template, TemplateDraft>({
    items: templates,
    getId: (t) => t.id,
    urlSelection: { selectedId: leaf.leafId, onSelect: leaf.onSelect },
    blank: templateBlank,
    toInput: templateToInput,
    validate: (draft, others, base) =>
      templateValidate(
        draft,
        others.map((o) => ({ name: o.name, kind: o.kind })),
        base?.name,
      ),
    differs: templateDiffers,
    normalize: templateNormalize,
    create: (input) =>
      projectTemplatesApi.create({ kind: input.kind, ...templateToPatch(input) }, ws),
    // No `kind` — the backend refuses to re-kind a stored template, and the form freezes the
    // control to match, so there is nothing here to send.
    update: (id, input) => projectTemplatesApi.update(id, templateToPatch(input)),
    remove: (t) => projectTemplatesApi.remove(t.id),
    // Names what deleting a template actually does, which is what makes it safe: nothing it has
    // already made is touched. A board does not become invalid because the shape it was stamped
    // from was retired.
    confirmDelete: (t) =>
      `Delete "${t.name}"? Nothing it has already created is affected — only the template goes.`,
    refresh: reload,
    createLabel: "New template",
  });

  // PUBLISH the templates as a deeper rail level + register the editor's unsaved-work guard.
  useMasterDetailLevel({
    id: "project-templates-list",
    title: "Templates",
    form,
    items: templates,
    getId: (t) => t.id,
    getLabel: (t) => t.name,
    getSublabel: templateSublabel,
    itemIcon: <FileStack size={16} aria-hidden />,
    newLabel: "New template",
    leaf,
    emptyLabel: templates === null ? "Loading…" : "No templates yet.",
    // The spinner before "Templates". `emptyLabel` covers only the FIRST read — once the list is
    // cached the rows are on screen from the first frame, and this is the only thing that says a
    // revalidation is happening behind them.
    busy: isFetching,
    onNew: () => setNewOpen(true),
    overviewHelp:
      "A shape this workspace stamps out repeatedly — a card and its checklist, or a whole board.",
  });

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <FeatureTitle title={title} />
      <MasterDetailLeaf
        form={form}
        error={loadError}
        trailing={renderRecordAffordance?.({
          path: "/project/templates/{id}",
          pathValues: { id: form.selectedId },
          title: "Template API",
        })}
        emptyTitle={
          templates === null ? "Loading…" : "Select a template to edit, or create a new one."
        }
        renderDetail={(draft) => (
          <div key={form.detailKey} className="flex flex-col gap-6">
            <TemplateDetail
              title="Template"
              draft={draft}
              onChange={form.onChange}
              error={form.error}
              // Frozen for a saved row, open while creating — the one difference between the two
              // places this form appears.
              kindLocked={!form.creating}
            />
          </div>
        )}
      />
      {newOpen && (
        <CreateResourceDialog
          ariaLabel="New template"
          heading="New template"
          blank={templateBlank}
          validate={(d) =>
            templateValidate(
              d,
              (templates ?? []).map((t) => ({ name: t.name, kind: t.kind })),
            )
          }
          create={(d) => projectTemplatesApi.create({ kind: d.kind, ...templateToPatch(d) }, ws)}
          onClose={() => setNewOpen(false)}
          onCreated={(created) => {
            setNewOpen(false);
            void reload();
            leaf.onSelect(created.id);
          }}
          renderForm={(draft, onChange, error) => (
            <TemplateDetail draft={draft} onChange={onChange} error={error} />
          )}
        />
      )}
    </div>
  );
}

/* ── A template as a chip, for the pickers ────────────────────────────────── */

/** What a template is, as one small badge — used where a template is CHOSEN rather than edited, so
 *  a picker's option carries the same phrase the library's rail row does. */
export function TemplateKindBadge({ template }: { template: Template }): ReactElement {
  return (
    <Badge variant={template.kind === "project" ? "blue" : "neutral"}>
      {templateSublabel(template)}
    </Badge>
  );
}
