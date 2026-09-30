"use client";

import {
  useState,
  useEffect,
  useMemo,
  useCallback,
  useRef,
  type ReactElement,
  type ReactNode,
} from "react";
import { useRouter } from "next/navigation";
import { FeatureTitle } from "@agentic-toolkit/resource";
import { useQueries, useQueryClient } from "@tanstack/react-query";
import { Eye, EyeOff, Plus, Trash2 } from "lucide-react";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { Checkbox } from "@agenticdevelopertoolkit/ui/components/checkbox";
import { Select } from "@agenticdevelopertoolkit/ui/components/select";
import { Switch } from "@agenticdevelopertoolkit/ui/components/switch";
import { Separator } from "@agenticdevelopertoolkit/ui/components/separator";
import { Disclosure } from "@agenticdevelopertoolkit/ui/components/disclosure";
import { SectionHeader } from "@agenticdevelopertoolkit/ui/blocks/section-header";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { railLinkVariants } from "@agenticdevelopertoolkit/ui/lib/nav-rail";
import { noAutofillProps } from "@agenticdevelopertoolkit/ui/lib/autofill";
import { cn } from "../lib/utils";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";
import { UnsavedChangesGuard } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-guard";
import {
  useProviders,
  useClients,
  useCreateClient,
  useUpdateClient,
  useDeleteClient,
  useProviderTemplates,
  useCreateProvider,
  useUpdateProvider,
  useDeleteProvider,
  useLinkProvider,
  useUnlinkProvider,
  useAuthMethods,
  useUpdateAuthMethod,
  type ClientShowResponse,
  type ProviderTemplate,
} from "../api/auth-config";
import { authedJson } from "../api/http";
import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";

function SecretInput({
  id,
  value,
  onChange,
  disabled,
  placeholder,
  className,
}: {
  id: string;
  value: string;
  onChange: (v: string) => void;
  disabled?: boolean;
  placeholder?: string;
  className?: string;
}) {
  const [visible, setVisible] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  function toggle() {
    if (visible) {
      if (timerRef.current) clearTimeout(timerRef.current);
      timerRef.current = null;
      setVisible(false);
      return;
    }
    setVisible(true);
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => {
      setVisible(false);
      timerRef.current = null;
    }, 5000);
  }

  return (
    <div className="relative">
      <Input
        id={id}
        type={visible ? "text" : "password"}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        disabled={disabled}
        placeholder={placeholder}
        className={cn(className, "pr-10")}
      />
      {/* `icon-sm` (size-7) rather than `icon` (size-8): the Input above reserves a
          `pr-10` gutter, and 8px of `right-2` plus a 32px box fills it exactly, leaving
          the glyph flush against the border. `tabIndex={-1}` stays — the reveal is a
          convenience on the field it decorates, not a tab stop between fields. */}
      <Button
        type="button"
        variant="ghost"
        size="icon-sm"
        onClick={toggle}
        disabled={disabled || !value}
        tabIndex={-1}
        aria-label={visible ? "Hide secret" : "Show secret for 5 seconds"}
        className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground"
      >
        {visible ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
      </Button>
    </div>
  );
}

type RowStatus = "existing" | "new" | "deleted";

function normalizeOrigins(origins: readonly string[]): string[] {
  return origins.map((o) => o.trim()).filter((o) => o.length > 0);
}

function originsEqual(a: readonly string[], b: readonly string[]): boolean {
  if (a.length !== b.length) return false;
  const sa = [...a].sort();
  const sb = [...b].sort();
  return sa.every((v, i) => v === sb[i]);
}

interface EntryPointDraft {
  localId: string;
  originalSlug: string | null;
  slug: string;
  name: string;
  origins: string[];
  status: RowStatus;
}

interface ProviderDraft {
  localId: string;
  originalSlug: string | null;
  slug: string;
  templateSlug: string | null;
  name: string;
  clientId: string;
  clientSecret: string;
  globallyEnabled: boolean;
  enabledForEntryPoint: Record<string, boolean>;
  status: RowStatus;
}

interface AuthSnapshot {
  entryPoints: EntryPointDraft[];
  providers: ProviderDraft[];
}

const TOPICS = [{ id: "oauth", label: "OAuth" }] as const;
type TopicId = (typeof TOPICS)[number]["id"];

export function AuthenticationPane({ help }: { help?: ReactNode } = {}): ReactElement {
  const router = useRouter();
  const providersQ = useProviders();
  const clientsQ = useClients();
  const methodsQ = useAuthMethods();
  const templatesQ = useProviderTemplates();
  const qc = useQueryClient();

  const externalClients = useMemo(
    () => clientsQ.data?.filter((c) => !c.isInternal) ?? [],
    [clientsQ.data],
  );

  const clientDetailsQueries = useQueries({
    queries: externalClients.map((c) => ({
      queryKey: ["admin", "oauth", "clients", c.slug],
      queryFn: () =>
        authedJson<ClientShowResponse>(`/api/oauth/clients/${c.slug}`),
    })),
  });

  const allLoaded =
    !providersQ.isLoading &&
    !clientsQ.isLoading &&
    !methodsQ.isLoading &&
    !templatesQ.isLoading &&
    clientDetailsQueries.every((q) => !q.isLoading);

  const buildSnapshot = useCallback((): AuthSnapshot => {
    const eps: EntryPointDraft[] = externalClients.map((c) => ({
      localId: c.slug,
      originalSlug: c.slug,
      slug: c.slug,
      name: c.name,
      origins: [...c.allowedReturnOrigins],
      status: "existing",
    }));

    const provs: ProviderDraft[] = (providersQ.data ?? []).map((p) => {
      const enabledForEntryPoint: Record<string, boolean> = {};
      for (const ep of eps) {
        if (!ep.originalSlug) continue;
        const i = externalClients.findIndex((c) => c.slug === ep.originalSlug);
        const linked =
          clientDetailsQueries[i]?.data?.providers.some(
            (lp) => lp.slug === p.slug,
          ) ?? false;
        enabledForEntryPoint[ep.localId] = linked;
      }
      const method = methodsQ.data?.find((m) => m.method === `oauth-${p.slug}`);
      return {
        localId: p.slug,
        originalSlug: p.slug,
        slug: p.slug,
        templateSlug: null,
        name: p.name,
        clientId: p.clientId,
        clientSecret: "",
        globallyEnabled: method?.enabled ?? true,
        enabledForEntryPoint,
        status: "existing",
      };
    });

    return { entryPoints: eps, providers: provs };
  }, [externalClients, providersQ.data, methodsQ.data, clientDetailsQueries]);

  const [snapshot, setSnapshot] = useState<AuthSnapshot | null>(null);
  const [isDirty, setIsDirty] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [activeTopic, setActiveTopic] = useState<TopicId>(TOPICS[0].id);
  const [discardOpen, setDiscardOpen] = useState(false);

  useEffect(() => {
    if (allLoaded && snapshot === null) {
      setSnapshot(buildSnapshot());
    }
  }, [allLoaded, snapshot, buildSnapshot]);

  function markDirty() {
    setIsDirty(true);
    setSaveError(null);
  }

  function updateEntryPoint(localId: string, patch: Partial<EntryPointDraft>) {
    if (!snapshot) return;
    setSnapshot({
      ...snapshot,
      entryPoints: snapshot.entryPoints.map((ep) =>
        ep.localId === localId ? { ...ep, ...patch } : ep,
      ),
    });
    markDirty();
  }

  function updateProvider(localId: string, patch: Partial<ProviderDraft>) {
    if (!snapshot) return;
    setSnapshot({
      ...snapshot,
      providers: snapshot.providers.map((p) =>
        p.localId === localId ? { ...p, ...patch } : p,
      ),
    });
    markDirty();
  }

  function addEntryPoint() {
    if (!snapshot) return;
    setSnapshot({
      ...snapshot,
      entryPoints: [
        ...snapshot.entryPoints,
        {
          localId: `new-ep-${Date.now()}`,
          originalSlug: null,
          slug: "",
          name: "",
          origins: [""],
          status: "new",
        },
      ],
    });
    markDirty();
  }

  function addProvider() {
    if (!snapshot) return;
    const templates = Object.values(templatesQ.data?.templates ?? {});
    const first = templates[0];
    if (!first) return;
    const enabledForEntryPoint: Record<string, boolean> = {};
    for (const ep of snapshot.entryPoints) {
      if (ep.status !== "deleted") enabledForEntryPoint[ep.localId] = false;
    }
    setSnapshot({
      ...snapshot,
      providers: [
        ...snapshot.providers,
        {
          localId: `new-prov-${Date.now()}`,
          originalSlug: null,
          slug: "",
          templateSlug: first.slug,
          name: first.name,
          clientId: "",
          clientSecret: "",
          globallyEnabled: true,
          enabledForEntryPoint,
          status: "new",
        },
      ],
    });
    markDirty();
  }

  function toggleEntryPointDelete(localId: string) {
    if (!snapshot) return;
    const ep = snapshot.entryPoints.find((e) => e.localId === localId);
    if (!ep) return;
    if (ep.status === "new") {
      setSnapshot({
        ...snapshot,
        entryPoints: snapshot.entryPoints.filter((e) => e.localId !== localId),
      });
    } else {
      updateEntryPoint(localId, {
        status: ep.status === "deleted" ? "existing" : "deleted",
      });
      return;
    }
    markDirty();
  }

  function toggleProviderDelete(localId: string) {
    if (!snapshot) return;
    const p = snapshot.providers.find((pp) => pp.localId === localId);
    if (!p) return;
    if (p.status === "new") {
      setSnapshot({
        ...snapshot,
        providers: snapshot.providers.filter((pp) => pp.localId !== localId),
      });
    } else {
      updateProvider(localId, {
        status: p.status === "deleted" ? "existing" : "deleted",
      });
      return;
    }
    markDirty();
  }

  function handleCancel() {
    if (isDirty) {
      setDiscardOpen(true);
      return;
    }
    doDiscard();
  }

  function doDiscard() {
    setSnapshot(buildSnapshot());
    setIsDirty(false);
    setSaveError(null);
  }

  const createClient = useCreateClient();
  const updateClient = useUpdateClient();
  const deleteClient = useDeleteClient();
  const createProvider = useCreateProvider();
  const updateProviderMut = useUpdateProvider();
  const deleteProvider = useDeleteProvider();
  const linkProvider = useLinkProvider();
  const unlinkProvider = useUnlinkProvider();
  const updateMethod = useUpdateAuthMethod();

  async function handleSave() {
    if (!snapshot) return;
    setSaving(true);
    setSaveError(null);

    try {
      const origEntryPoints = externalClients;
      const origProviders = providersQ.data ?? [];

      for (const ep of snapshot.entryPoints) {
        if (ep.status === "deleted" && ep.originalSlug) {
          await deleteClient.mutateAsync(ep.originalSlug);
        }
      }
      for (const p of snapshot.providers) {
        if (p.status === "deleted" && p.originalSlug) {
          await deleteProvider.mutateAsync(p.originalSlug);
        }
      }

      for (const ep of snapshot.entryPoints) {
        if (ep.status === "new") {
          const slug = ep.slug.trim();
          const origins = normalizeOrigins(ep.origins);
          if (!slug || !ep.name.trim() || origins.length === 0) continue;
          await createClient.mutateAsync({
            slug,
            name: ep.name.trim(),
            allowedReturnOrigins: origins,
            defaultEcosystemId: slug,
          });
        }
      }
      for (const p of snapshot.providers) {
        if (p.status === "new") {
          const slug = p.slug.trim();
          if (
            !p.templateSlug ||
            !slug ||
            !p.clientId.trim() ||
            !p.clientSecret.trim()
          ) {
            continue;
          }
          await createProvider.mutateAsync({
            templateSlug: p.templateSlug,
            slug,
            clientId: p.clientId.trim(),
            clientSecret: p.clientSecret.trim(),
          });
        }
      }

      for (const ep of snapshot.entryPoints) {
        if (ep.status !== "existing" || !ep.originalSlug) continue;
        const orig = origEntryPoints.find((c) => c.slug === ep.originalSlug);
        if (!orig) continue;
        const slugChanged = orig.slug !== ep.slug.trim() && ep.slug.trim() !== "";
        const nameChanged = orig.name !== ep.name.trim();
        const parsedOrigins = normalizeOrigins(ep.origins);
        const originsChanged = !originsEqual(
          orig.allowedReturnOrigins,
          parsedOrigins,
        );
        if (slugChanged || nameChanged || originsChanged) {
          await updateClient.mutateAsync({
            slug: ep.originalSlug,
            ...(slugChanged ? { slug: ep.slug.trim() } : {}),
            ...(nameChanged ? { name: ep.name.trim() } : {}),
            ...(originsChanged
              ? { allowedReturnOrigins: parsedOrigins }
              : {}),
          });
        }
      }

      for (const p of snapshot.providers) {
        if (p.status !== "existing" || !p.originalSlug) continue;
        const orig = origProviders.find((op) => op.slug === p.originalSlug);
        if (!orig) continue;
        const slugChanged = orig.slug !== p.slug.trim() && p.slug.trim() !== "";
        const nameChanged = orig.name !== p.name.trim();
        const clientIdChanged = orig.clientId !== p.clientId.trim();
        const secretChanged = p.clientSecret.trim() !== "";
        if (slugChanged || nameChanged || clientIdChanged || secretChanged) {
          await updateProviderMut.mutateAsync({
            slug: p.originalSlug,
            ...(slugChanged ? { slug: p.slug.trim() } : {}),
            ...(nameChanged ? { displayName: p.name.trim() } : {}),
            ...(clientIdChanged ? { clientId: p.clientId.trim() } : {}),
            ...(secretChanged ? { clientSecret: p.clientSecret.trim() } : {}),
          });
        }
      }

      for (const p of snapshot.providers) {
        if (p.status === "deleted" || !p.originalSlug) continue;
        const method = methodsQ.data?.find(
          (m) => m.method === `oauth-${p.originalSlug}`,
        );
        if (method && method.enabled !== p.globallyEnabled) {
          await updateMethod.mutateAsync({
            method: method.method,
            enabled: p.globallyEnabled,
          });
        }
      }

      for (const p of snapshot.providers) {
        if (p.status === "deleted" || !p.originalSlug) continue;
        const providerSlug = p.slug.trim() || p.originalSlug;
        for (const ep of snapshot.entryPoints) {
          if (ep.status === "deleted" || ep.status === "new" || !ep.originalSlug) {
            continue;
          }
          const i = externalClients.findIndex(
            (c) => c.slug === ep.originalSlug,
          );
          const wasLinked =
            clientDetailsQueries[i]?.data?.providers.some(
              (lp) => lp.slug === p.originalSlug,
            ) ?? false;
          const isLinked = p.enabledForEntryPoint[ep.localId] ?? false;
          const clientSlug = ep.slug.trim() || ep.originalSlug;
          if (wasLinked && !isLinked) {
            await unlinkProvider.mutateAsync({
              clientSlug,
              providerSlug,
            });
          } else if (!wasLinked && isLinked) {
            await linkProvider.mutateAsync({
              clientSlug,
              providerSlug,
            });
          }
        }
      }

      await qc.invalidateQueries({ queryKey: ["admin", "oauth"] });
      await qc.invalidateQueries({ queryKey: ["admin", "auth-methods"] });
      setSnapshot(null);
      setIsDirty(false);
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "authentication-config", step: "save" });
      setSaveError(err instanceof Error ? err.message : "Failed to save.");
    } finally {
      setSaving(false);
    }
  }

  const templatesList = useMemo(
    () => Object.values(templatesQ.data?.templates ?? {}),
    [templatesQ.data],
  );

  if (!snapshot) {
    return <p className="text-muted-foreground">Loading...</p>;
  }

  const activeEntryPoints = snapshot.entryPoints.filter(
    (ep) => ep.status !== "deleted" || ep.originalSlug,
  );

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <FeatureTitle title="Authentication" help={help} />
      <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto px-6 pb-8 pt-2">
      <div className="mb-8">
        <p className="text-sm text-muted-foreground">
          Configure entry points (apps that sign users in here) and identity
          providers.
        </p>
      </div>

      <div className="grid grid-cols-[200px_1fr] min-h-[calc(100vh-200px)]">
        <aside className="border-r border-border pr-4 pt-2">
          <nav>
            <ul className="space-y-1">
              {TOPICS.map((t) => (
                <li key={t.id}>
                  <button
                    type="button"
                    onClick={() => setActiveTopic(t.id)}
                    aria-current={activeTopic === t.id ? "page" : undefined}
                    className={cn(
                      railLinkVariants({ active: activeTopic === t.id }),
                      "w-full text-left",
                    )}
                  >
                    {t.label}
                  </button>
                </li>
              ))}
            </ul>
          </nav>
        </aside>

        <div className="pl-8 pr-8 pb-8">
          {activeTopic === "oauth" && (
            <>
              <section className="mb-10">
                <SectionHeader
                  title="Entry points"
                  className="mb-3"
                  actions={
                    <Button variant="outline" size="sm" onClick={addEntryPoint}>
                      + Add entry point
                    </Button>
                  }
                />

                {activeEntryPoints.length === 0 && (
                  <p className="text-sm text-muted-foreground">
                    No entry points yet.
                  </p>
                )}

                <div className="space-y-3">
                  {activeEntryPoints.map((ep) => (
                    <EntryPointCard
                      key={ep.localId}
                      ep={ep}
                      onChange={(patch) => updateEntryPoint(ep.localId, patch)}
                      onToggleDelete={() => toggleEntryPointDelete(ep.localId)}
                    />
                  ))}
                </div>
              </section>

              <Separator className="my-8" />

              <section className="mb-10">
                <SectionHeader
                  title="Providers"
                  className="mb-3"
                  actions={
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={addProvider}
                      disabled={!templatesQ.data}
                    >
                      + Add provider
                    </Button>
                  }
                />

                {snapshot.providers.length === 0 && (
                  <p className="text-sm text-muted-foreground">
                    No providers yet.
                  </p>
                )}

                <div className="space-y-3">
                  {snapshot.providers.map((p) => (
                    <ProviderCard
                      key={p.localId}
                      provider={p}
                      entryPoints={snapshot.entryPoints.filter(
                        (ep) => ep.status !== "deleted",
                      )}
                      templates={templatesList}
                      onChange={(patch) => updateProvider(p.localId, patch)}
                      onToggleDelete={() => toggleProviderDelete(p.localId)}
                    />
                  ))}
                </div>
              </section>

              <div className="border-t border-border pt-4 mt-4 flex items-center justify-between gap-4">
                {/* A live region for the same reason `EditActionBar` — the toolkit's twin of
                    this bar — makes its status cell one: the three branches swap inside a node
                    that is always mounted, so the cell is what announces, not the red span.
                    `status` (polite), because "All changes saved." shares the slot. */}
                <div role="status" className="text-sm text-muted-foreground">
                  {saveError ? (
                    <span className="text-destructive">{saveError}</span>
                  ) : isDirty ? (
                    "You have unsaved changes."
                  ) : (
                    "All changes saved."
                  )}
                </div>
                <div className="flex gap-2">
                  <Button
                    variant="outline"
                    onClick={handleCancel}
                    disabled={!isDirty || saving}
                  >
                    Cancel
                  </Button>
                  <Button onClick={handleSave} disabled={!isDirty || saving}>
                    {saving ? "Saving..." : "Save"}
                  </Button>
                </div>
              </div>
            </>
          )}
        </div>
      </div>

      <UnsavedChangesGuard when={isDirty} onNavigate={(href) => router.push(href)} />

      <AlertModal
        open={discardOpen}
        destructive
        title="Discard all unsaved changes?"
        description="Your edits will be lost. This cannot be undone."
        cancelLabel="Keep editing"
        onCancel={() => setDiscardOpen(false)}
        confirmLabel="Discard"
        onConfirm={() => {
          setDiscardOpen(false);
          doDiscard();
        }}
      />
      </div>
    </div>
  );
}

/**
 * A card heading that becomes editable in place. Deliberately NOT the `Input` and
 * `Button` primitives, and this is the recorded reason rather than an oversight:
 * an in-place editor's whole job is to keep the heading looking like a heading, so
 * that clicking it edits the title you were already reading. `Input` would draw a
 * field shell (border, surface, radius) around the card's title; `Button` would
 * impose `text-sm font-medium`, and its `link` variant would underline on hover,
 * which reads as navigation on something that isn't a link. Both halves therefore
 * inherit the heading's own `text-lg font-semibold text-primary`, and the editing
 * state is marked by the one thing that must change — a bottom rule where the
 * button's is transparent, so the two states are the same height and the title
 * does not jump when you click it.
 */
function EditableTitle({
  value,
  onChange,
  disabled,
  placeholder,
}: {
  value: string;
  onChange: (v: string) => void;
  disabled?: boolean;
  /** Doubles as the field's accessible name — it names the thing ("Provider name"),
   *  which is what the empty state needs and what a screen reader needs. */
  placeholder?: string;
}) {
  const [editing, setEditing] = useState(false);

  useEffect(() => {
    if (disabled) setEditing(false);
  }, [disabled]);

  if (editing) {
    return (
      <input
        /* eslint-disable-next-line jsx-a11y/no-autofocus -- intentional focus-on-open for a user-invoked inline edit field */
        autoFocus
        aria-label={placeholder ?? "Title"}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        onClick={(e) => e.stopPropagation()}
        onBlur={() => setEditing(false)}
        onKeyDown={(e) => {
          if (e.key === "Enter" || e.key === "Escape") setEditing(false);
        }}
        placeholder={placeholder}
        className="text-lg font-semibold text-primary bg-transparent outline-none border-b border-primary/40 w-64"
        {...noAutofillProps}
      />
    );
  }

  return (
    <button
      type="button"
      onClick={(e) => { e.stopPropagation(); setEditing(true); }}
      disabled={disabled}
      className="text-lg font-semibold text-primary text-left truncate hover:opacity-80 transition-opacity disabled:cursor-not-allowed border-b border-transparent"
    >
      {value || <span className="text-muted-foreground italic">{placeholder ?? "Untitled"}</span>}
    </button>
  );
}

function EntryPointCard({
  ep,
  onChange,
  onToggleDelete,
}: {
  ep: EntryPointDraft;
  onChange: (patch: Partial<EntryPointDraft>) => void;
  onToggleDelete: () => void;
}) {
  const deleted = ep.status === "deleted";
  return (
    <Disclosure
      className={cn("transition-opacity", deleted && "opacity-50")}
      defaultOpen={ep.status === "new"}
      title={
        <EditableTitle
          value={ep.name}
          onChange={(v) => onChange({ name: v })}
          disabled={deleted}
          placeholder="Entry point name"
        />
      }
    >
      <div className="space-y-4">
        <Field label="Slug">
          <Input
            value={ep.slug}
            onChange={(e) => onChange({ slug: e.target.value })}
            disabled={deleted}
            placeholder="adh"
            className="font-mono"
          />
        </Field>

        <div className="space-y-1.5">
          <div className="flex items-center justify-between">
            <Label>Allowed Return Origins</Label>
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={deleted}
              onClick={() => onChange({ origins: [...ep.origins, ""] })}
            >
              <Plus className="size-4 mr-1" />
              Add Return Origin
            </Button>
          </div>
          <div className="space-y-2">
            {ep.origins.map((origin, i) => (
              <div
                key={`${ep.localId}-origin-${i}`}
                className="flex items-center gap-2"
              >
                <Input
                  value={origin}
                  onChange={(e) => {
                    const next = [...ep.origins];
                    next[i] = e.target.value;
                    onChange({ origins: next });
                  }}
                  disabled={deleted}
                  placeholder="https://agenticdeveloperhub.com"
                  className="font-mono flex-1"
                />
                <Button
                  type="button"
                  variant="destructive-ghost"
                  size="icon"
                  disabled={deleted || ep.origins.length <= 1}
                  onClick={() => {
                    const next = ep.origins.filter((_, j) => j !== i);
                    onChange({ origins: next.length === 0 ? [""] : next });
                  }}
                  aria-label="Remove return origin"
                  className="shrink-0"
                >
                  <Trash2 className="size-4" />
                </Button>
              </div>
            ))}
          </div>
        </div>

        <div className="flex justify-end pt-2">
          {deleted ? (
            <Button variant="outline" size="sm" onClick={onToggleDelete}>
              Restore
            </Button>
          ) : (
            <ConfirmDialog
              title="Delete entry point"
              description={`Are you sure you want to delete "${ep.name || ep.slug || "this entry point"}"? This will take effect when you save.`}
              onConfirm={onToggleDelete}
            />
          )}
        </div>
      </div>
    </Disclosure>
  );
}

function ProviderCard({
  provider,
  entryPoints,
  templates,
  onChange,
  onToggleDelete,
}: {
  provider: ProviderDraft;
  entryPoints: EntryPointDraft[];
  templates: ProviderTemplate[];
  onChange: (patch: Partial<ProviderDraft>) => void;
  onToggleDelete: () => void;
}) {
  const deleted = provider.status === "deleted";
  const isNew = provider.status === "new";
  return (
    <Disclosure
      className={cn("transition-opacity", deleted && "opacity-50")}
      defaultOpen={isNew}
      title={
        <EditableTitle
          value={provider.name}
          onChange={(v) => onChange({ name: v })}
          disabled={deleted}
          placeholder="Provider name"
        />
      }
    >
      <div className="space-y-4">
        {isNew && (
          <Field label="Type">
            <Select
              aria-label="Type"
              value={provider.templateSlug ?? ""}
              onChange={(e) => {
                const t = templates.find((tt) => tt.slug === e.target.value);
                onChange({
                  templateSlug: e.target.value,
                  name: t?.name ?? provider.name,
                });
              }}
              disabled={deleted}
            >
              {templates.map((t) => (
                <option key={t.slug} value={t.slug}>
                  {t.name}
                </option>
              ))}
            </Select>
          </Field>
        )}

        <Field label="Slug">
          <Input
            value={provider.slug}
            onChange={(e) => onChange({ slug: e.target.value })}
            disabled={deleted}
            placeholder="google"
            className="font-mono"
          />
        </Field>

        <Field label="Client ID">
          <Input
            value={provider.clientId}
            onChange={(e) => onChange({ clientId: e.target.value })}
            disabled={deleted}
            className="font-mono"
          />
        </Field>

        <Field label="Client Secret">
          <SecretInput
            id={`p-sec-${provider.localId}`}
            value={provider.clientSecret}
            onChange={(v) => onChange({ clientSecret: v })}
            disabled={deleted}
            placeholder={isNew ? "" : "leave blank to keep current"}
            className="font-mono"
          />
        </Field>

        <Separator />

        <div className="flex items-center justify-between">
          <Label
            htmlFor={`p-global-${provider.localId}`}
            className="cursor-pointer"
          >
            Enabled globally
          </Label>
          <Switch
            id={`p-global-${provider.localId}`}
            checked={provider.globallyEnabled}
            onCheckedChange={(v) => onChange({ globallyEnabled: v })}
            disabled={deleted}
          />
        </div>

        {entryPoints.length > 0 && (
          <div className="space-y-2">
            <p className="text-xs text-muted-foreground">
              Enabled for entry points:
            </p>
            <div className="space-y-2 pl-2">
              {entryPoints.map((ep) => {
                const checked =
                  provider.enabledForEntryPoint[ep.localId] ?? false;
                return (
                  <div key={ep.localId} className="flex items-center gap-2">
                    <Checkbox
                      id={`p-ep-${provider.localId}-${ep.localId}`}
                      checked={checked}
                      onCheckedChange={(v) =>
                        onChange({
                          enabledForEntryPoint: {
                            ...provider.enabledForEntryPoint,
                            [ep.localId]: v === true,
                          },
                        })
                      }
                      disabled={deleted || ep.status === "new"}
                    />
                    <Label
                      htmlFor={`p-ep-${provider.localId}-${ep.localId}`}
                      className="cursor-pointer text-sm"
                    >
                      {ep.name || (
                        <span className="text-muted-foreground italic">
                          (unnamed)
                        </span>
                      )}
                      {ep.status === "new" && (
                        <span className="text-xs text-muted-foreground ml-2">
                          — save first to link
                        </span>
                      )}
                    </Label>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        <div className="flex justify-end pt-2">
          {deleted ? (
            <Button variant="outline" size="sm" onClick={onToggleDelete}>
              Restore
            </Button>
          ) : (
            <ConfirmDialog
              title="Delete provider"
              description={`Are you sure you want to delete "${provider.name || provider.slug || "this provider"}"? This will take effect when you save.`}
              onConfirm={onToggleDelete}
            />
          )}
        </div>
      </div>
    </Disclosure>
  );
}
