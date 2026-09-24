"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AuthHttpError } from "@agentic-toolkit/auth";

import {
  checkSlugAvailable,
  ME_QUERY_KEY,
  updateMe,
  useCurrentUser,
} from "../api/auth";
import { listContacts } from "../api/account";
import {
  listSocialLinks,
  listAddresses,
  getPrivacyGrants,
  socialLinksKey,
  addressesKey,
  PRIVACY_KEY,
  type PrivacyGrant,
} from "@agentic-toolkit/data/profile";
import { slugify, validateSlug } from "@agenticdevelopertoolkit/ui/lib/slug";
import {
  PrivacyLevelSelect,
  PRIVACY_WIRE_VALUE,
  PRIVACY_LEVEL_FROM_WIRE,
  type PrivacyLevel,
} from "@agenticdevelopertoolkit/ui/components/privacy-level-select";
import { useSettingsDirty, SettingsBody } from "@agentic-toolkit/resource";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { UserCard, UserCardSkeleton, type UserCardDto } from "@agenticdevelopertoolkit/ui/blocks";
import { EditActionBar } from "@agentic-toolkit/resource";
import { DetailSection } from "@agentic-toolkit/resource";
import { AvatarSection } from "./profile/AvatarSection";

// ── Draft type ─────────────────────────────────────────────────────────────────

// Only the fields the user has explicitly touched
type Edits = {
  name?: string;
  slug?: string;
  profileVisibility?: PrivacyLevel;
};

// ── Component ──────────────────────────────────────────────────────────────────

export interface ProfilePanelProps {
  /** The HOST's reserved slug words (its URL-namespace protection) — rejected on save.
   *  Injected rather than imported: this package is MECHANISM tier and must never import
   *  an `adh*`-scoped VOCABULARY package (the reserved list is `reservedWorkspaceSlugs()`
   *  in adh's `packages/adh/src/site/reservedSlugs.ts`), so the host binds its own set here
   *  — the same seam `@agenticdevelopertoolkit/ui/lib/slug`'s `validateSlug` already documents via
   *  its own `reserved` parameter.
   *
   *  REQUIRED, and deliberately not optional. Every host has a URL namespace to protect,
   *  so there is no host for which "no reserved words" is the right answer — only hosts
   *  that forgot. Optional, the omission degraded SILENTLY: the panel let the user type a
   *  reserved handle, showed it as available, and surfaced the collision only as a server
   *  error on Save. A host that genuinely wants generic-only validation says so out loud
   *  by passing an empty set. */
  reservedSlugs: ReadonlySet<string>;

  /** The host's public profile URL for a slug — e.g. `https://agenticdeveloperhub.com/mike`.
   *  Injected for the same reason `reservedSlugs` is: this package is MECHANISM tier and must
   *  not import an `adh*`-scoped VOCABULARY package, and the hub's origin is vocabulary. The
   *  host mints it from the registry (`siteUrl('hub', `/${slug}`, location.hostname)`); a
   *  component that writes `agenticdeveloperhub.com` into a string is the defect this replaces,
   *  and it was there twice.
   *
   *  REQUIRED, and deliberately not optional, on the same argument the prop above makes: every
   *  host has an origin, so there is no host for which "no URL" is right — only hosts that
   *  forgot, and the omission would degrade silently into a panel that shows the user no
   *  address at all. */
  profileUrlFor: (slug: string) => string;
}

export function ProfilePanel({ reservedSlugs, profileUrlFor }: ProfilePanelProps) {
  const meQuery = useCurrentUser();
  const me = meQuery.data;
  const qc = useQueryClient();
  const { reportDirty } = useSettingsDirty();

  // ── Identity edit state (name / slug / public toggle) ─────────────────────
  // Sparse "edits" object — only the fields the user has explicitly changed.
  // Cancel: reset to {} so current form values revert to server data.
  // Save success: reset to {} and invalidate server data query.
  const [edits, setEdits] = useState<Edits>({});
  const [saveError, setSaveError] = useState<string | null>(null);

  // Derived current form values
  const serverName = me?.name ?? "";
  const serverSlug = me?.slug ?? "";
  const serverProfileVisibility = PRIVACY_LEVEL_FROM_WIRE(
    me?.profileVisibility ?? "public",
  );
  const name = edits.name ?? serverName;
  const slug = edits.slug ?? serverSlug;
  const profileVisibility = edits.profileVisibility ?? serverProfileVisibility;

  // ── Slug availability (debounced) ─────────────────────────────────────────
  const [debouncedSlug, setDebouncedSlug] = useState(slug);
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSlug(slug), 350);
    return () => clearTimeout(timer);
  }, [slug]);

  // slug (login handle) is required — validateSlug("") returns "Slug is required.",
  // so clearing the handle surfaces an error and blocks save instead of silently
  // disabling it. `reservedSlugs` (host-injected, see the prop doc) also rejects a
  // namespace collision instantly, before the debounced availability probe fires.
  const clientSlugError = validateSlug(slug, reservedSlugs);

  const shouldCheckAvailability =
    Boolean(debouncedSlug) &&
    !validateSlug(debouncedSlug, reservedSlugs) &&
    debouncedSlug !== serverSlug;

  const slugAvailQuery = useQuery({
    queryKey: ["auth", "slug-available", debouncedSlug],
    queryFn: () => checkSlugAvailable(debouncedSlug),
    enabled: shouldCheckAvailability,
    retry: false,
    staleTime: 30_000,
  });

  type SlugStatus = "idle" | "checking" | "available" | "unavailable" | "avail-error";
  const slugStatus: SlugStatus = !slug
    ? "idle"
    // Only show "checking" when the slug differs from BOTH the debounced value AND
    // the server slug — guards spurious "Checking…" on panel open before the
    // debounce settles.
    : slug !== debouncedSlug && slug !== serverSlug
      ? "checking"
      : !shouldCheckAvailability
        ? "idle"
        : slugAvailQuery.isFetching
          ? "checking"
          : slugAvailQuery.data?.available
            ? "available"
            : slugAvailQuery.data
              ? "unavailable"
              : slugAvailQuery.isError
                ? "avail-error"
                : "idle";
  const slugUnavailReason =
    slugAvailQuery.data?.available === false
      ? slugAvailQuery.data.reason
      : undefined;

  // ── Dirty + unsaved-edits tracking ────────────────────────────────────────
  // A real value diff against the loaded row, not a touched-flag: `edits` only
  // records which fields the user has TOUCHED, so `Object.keys(edits).length > 0`
  // stays true after an edit-and-revert (e.g. type a char, then delete it back to
  // the original) even though the draft is byte-identical to what loaded. Save
  // must enable exactly when the draft differs from the server value — mirrors
  // handleSave's own per-field comparison below, so the two never disagree about
  // what counts as a real change.
  const dirty =
    (edits.name !== undefined && edits.name.trim() !== serverName) ||
    (edits.slug !== undefined && edits.slug !== serverSlug) ||
    (edits.profileVisibility !== undefined &&
      edits.profileVisibility !== serverProfileVisibility);
  useEffect(() => {
    reportDirty("profile", dirty);
    return () => reportDirty("profile", false);
  }, [dirty, reportDirty]);

  // ── Save mutation ──────────────────────────────────────────────────────────
  // Re-entrancy latch. `saveMutation.isPending` can't do this job: it is a RENDER value,
  // so two activations inside a single commit (a fast double-click before React paints
  // the disabled button) both read the pre-save `false` and both fire a PATCH — proven
  // by the "before the disabled state can render" test. A ref flips synchronously on the
  // way in and clears when the mutation settles, either way.
  const savingRef = useRef(false);
  const saveMutation = useMutation({
    mutationFn: updateMe,
    onSuccess: () => {
      setEdits({});
      setSaveError(null);
      qc.invalidateQueries({ queryKey: ME_QUERY_KEY });
    },
    onError: (err: unknown) => {
      if (err instanceof AuthHttpError && err.status === 409) {
        setSaveError("This slug is already taken — try a different one.");
      } else if (err instanceof Error) {
        setSaveError(err.message);
      } else {
        setSaveError("Could not save. Please try again.");
      }
    },
    onSettled: () => {
      savingRef.current = false;
    },
  });

  // ── Can-save guard ─────────────────────────────────────────────────────────
  const slugFieldChanged = "slug" in edits;
  // Shown only once the user edits the field — the same gate Save uses. A backend-minted handle
  // that fails today's rule otherwise sat under the field in red, blaming the user for a value
  // they never typed and could leave alone.
  const shownSlugError = slugFieldChanged ? clientSlugError : null;
  const slugClearToSave =
    !slugFieldChanged ||
    (!clientSlugError &&
      (slug === serverSlug ||
        slugStatus === "available" ||
        // Allow save when the availability check itself errored — the server
        // will validate; the user should not be stuck with a silently disabled Save.
        slugStatus === "avail-error"));
  // dirty && valid ONLY. The in-flight term is NOT folded in here: `canSave` is handed
  // to <EditActionBar> → <SaveCancelButtons>, which already applies `disabled={!canSave
  // || saving}` itself, so including it would express the same rule twice — and the
  // duplicate is what previously stood in for the missing re-entrancy guard below.
  //
  // `clientSlugError` is deliberately NOT a term of its own: it is computed from `slug`,
  // which falls back to the STORED handle, so a standalone `!clientSlugError` blocks every
  // save for an account whose existing slug fails today's rules (a word later added to the
  // host's reserved list; a format the validator tightened) — including a save that only
  // touches the display name, with "That slug is reserved." shown under a field the user
  // never opened and no way to clear it. `slugClearToSave` above already applies exactly
  // this check, gated on `slugFieldChanged`, which is the whole point of that term.
  const canSave = dirty && slugClearToSave && slugStatus !== "checking";

  function handleSave() {
    // The in-flight check lives HERE rather than in `canSave` (see above), and reads the
    // ref rather than `isPending` for the reason given at the latch: React Query's
    // `mutate` has no re-entrancy guard of its own.
    if (!canSave || savingRef.current) return;
    setSaveError(null);
    const body: Parameters<typeof updateMe>[0] = {};
    if (edits.name !== undefined && edits.name.trim() !== serverName) {
      body.name = edits.name.trim();
    }
    if (edits.slug !== undefined && edits.slug !== serverSlug) {
      body.slug = edits.slug;
    }
    if (
      edits.profileVisibility !== undefined &&
      edits.profileVisibility !== serverProfileVisibility
    ) {
      // The STORED word, not the UI literal — 'only-me' is spelled 'private' on the wire.
      body.profileVisibility = PRIVACY_WIRE_VALUE[edits.profileVisibility];
    }
    if (Object.keys(body).length === 0) {
      setEdits({});
      return;
    }
    savingRef.current = true;
    saveMutation.mutate(body);
  }

  function handleCancel() {
    setEdits({});
    setSaveError(null);
    saveMutation.reset();
  }

  const suggestedSlug = slugify(me?.name ?? "");
  const displaySlug = slug || serverSlug || suggestedSlug;

  // ── Card data queries (for live preview) ──────────────────────────────────

  // The preview shows the caller's OWN card, so both lists take the personal key — the same
  // accessor the editing sections invalidate through, so an edit refreshes this preview.
  const socialLinksQuery = useQuery({
    queryKey: socialLinksKey(),
    queryFn: () => listSocialLinks(),
    retry: false,
  });

  const addressesQuery = useQuery({
    queryKey: addressesKey(),
    queryFn: () => listAddresses(),
    retry: false,
  });

  // account/contacts is already managed by account.ts; re-use the same key so
  // NotificationsWorkspace cache hits benefit this query too.
  const contactsQuery = useQuery({
    queryKey: ["account", "contacts"],
    queryFn: listContacts,
    retry: false,
  });

  const privacyQuery = useQuery({
    queryKey: PRIVACY_KEY,
    queryFn: getPrivacyGrants,
    retry: false,
  });

  const grants: PrivacyGrant[] = privacyQuery.data ?? [];

  // ── Live preview DTO ───────────────────────────────────────────────────────
  // Owner always sees ALL their own data regardless of privacy settings —
  // privacy gates are applied by the backend when serving /public/users/{slug}.
  // /auth/me does not expose createdAt, so the preview omits "Member since"
  // (the backend adds the real account date on the public card endpoint).
  const previewDto = useMemo<UserCardDto | null>(() => {
    if (!me) return null;
    const contacts = contactsQuery.data ?? [];
    return {
      // Reflect in-progress edits so the card preview is truly WYSIWYG.
      slug: edits.slug ?? me.slug ?? me.email.split("@")[0] ?? "",
      displayName: edits.name ?? me.name ?? null,
      avatarUrl: me.avatarUrl ?? null,
      socialLinks: (socialLinksQuery.data ?? []).map((l) => ({
        platform: l.platform,
        url: l.url,
        handle: l.handle,
      })),
      emails: contacts
        .filter((c) => c.type === "email")
        .map((c) => c.value),
      phones: contacts
        .filter((c) => c.type === "phone")
        .map((c) => c.value),
      addresses: (addressesQuery.data ?? []).map((a) => ({
        label: a.label,
        line1: a.line1,
        line2: a.line2,
        city: a.city,
        region: a.region,
        postalCode: a.postalCode,
        country: a.country,
      })),
      personas: [], // personas are managed via their own workspace
    };
  }, [
    me,
    edits,
    socialLinksQuery.data,
    addressesQuery.data,
    contactsQuery.data,
  ]);

  // ── Loading / error guards ─────────────────────────────────────────────────
  if (meQuery.isLoading) {
    return (
      // In the body every section scrolls in, not centred: a status line sits where the form will.
      <SettingsBody>
        <p className="text-sm text-apt-text-muted">Loading…</p>
      </SettingsBody>
    );
  }
  if (meQuery.isError || !me) {
    return (
      <SettingsBody>
        <ErrorText error="Could not load profile. Refresh to try again." />
      </SettingsBody>
    );
  }

  // ── Render ─────────────────────────────────────────────────────────────────
  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <EditActionBar
        dirty={dirty}
        canSave={canSave}
        saving={saveMutation.isPending}
        onCancel={handleCancel}
        onSave={handleSave}
        status={
          saveError ? (
            <span className="text-apt-red">{saveError}</span>
          ) : saveMutation.isSuccess && !dirty ? (
            <span className="text-apt-green">Saved.</span>
          ) : null
        }
      />

      <SettingsBody>

        {/* ── Identity ─────────────────────────────────────────────── */}
        <DetailSection title="Public profile">
          <Card>
            <CardContent className="flex flex-col gap-5">
              {/* Display name */}
              <div className="flex flex-col gap-2">
                <Label htmlFor="profile-display-name">Display name</Label>
                <Input
                  id="profile-display-name"
                  value={name}
                  onChange={(e) => {
                    setEdits((prev) => ({ ...prev, name: e.target.value }));
                    setSaveError(null);
                  }}
                  placeholder="Your name"
                  autoComplete="name"
                />
                <p className="text-xs text-apt-text-muted">
                  Shown on your public profile and personas.
                </p>
              </div>

              {/* Slug */}
              <div className="flex flex-col gap-2">
                <Label htmlFor="profile-slug">Slug</Label>
                <Input
                  id="profile-slug"
                  value={slug}
                  onChange={(e) => {
                    setEdits((prev) => ({
                      ...prev,
                      slug: e.target.value.toLowerCase(),
                    }));
                    setSaveError(null);
                  }}
                  placeholder={suggestedSlug || "your-handle"}
                  aria-invalid={Boolean(shownSlugError)}
                  aria-describedby="profile-slug-hint"
                  autoCapitalize="none"
                  autoCorrect="off"
                  spellCheck={false}
                />
                <p id="profile-slug-hint" className="text-xs">
                  {shownSlugError ? (
                    <span className="text-apt-red">{shownSlugError}</span>
                  ) : slugStatus === "checking" ? (
                    <span className="text-apt-text-muted">Checking…</span>
                  ) : slugStatus === "available" ? (
                    <span className="text-apt-green">Available.</span>
                  ) : slugStatus === "unavailable" ? (
                    <span className="text-apt-red">
                      {slugUnavailReason === "taken"
                        ? "That slug is already taken."
                        : "Invalid slug format."}
                    </span>
                  ) : slugStatus === "avail-error" ? (
                    <span className="text-apt-red">
                      Couldn&apos;t check availability — try again
                    </span>
                  ) : (
                    <span className="text-apt-text-muted">
                      Your public URL:{" "}
                      <span className="text-apt-text">
                        {profileUrlFor(displaySlug || "…")}
                      </span>
                    </span>
                  )}
                </p>
              </div>

              {/* Profile visibility */}
              <div className="flex items-start justify-between gap-4">
                <div className="flex flex-col gap-1">
                  <Label className="leading-snug">
                    Profile visibility
                  </Label>
                  <p className="text-xs text-apt-text-muted">
                    Your profile is at{" "}
                    <span className="text-apt-text">
                      {profileUrlFor(displaySlug || "…")}
                    </span>
                  </p>
                </div>
                <div className="w-44">
                  <PrivacyLevelSelect
                    value={profileVisibility}
                    ariaLabel="Profile visibility"
                    onChange={(next) => {
                      setEdits((prev) => ({ ...prev, profileVisibility: next }));
                      setSaveError(null);
                    }}
                  />
                </div>
              </div>
            </CardContent>
          </Card>
        </DetailSection>

        {/* ── Avatar ───────────────────────────────────────────────── */}
        <AvatarSection me={me} grants={grants} />

        {/* ── Live preview ──────────────────────────────────────────── */}
        <DetailSection title="Card preview">
          <p className="text-xs text-apt-text-muted">
            This is how your profile card looks to you. Visibility settings
            above control what others see.
          </p>
          {previewDto ? (
            <UserCard user={previewDto} />
          ) : (
            <UserCardSkeleton />
          )}
        </DetailSection>
      </SettingsBody>
    </div>
  );
}
