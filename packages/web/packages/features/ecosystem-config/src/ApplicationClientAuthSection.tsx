"use client";

import { useRef, useState } from "react";

import { useResourceItemQuery, useResourceItemWriter } from "@agentic-toolkit/data";
import { clientAuthApi, type ApplicationClientAuth } from "@agentic-toolkit/data/ecosystem-config";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { DetailSection, useSettingsDraft } from "@agentic-toolkit/resource";
import { LoginRegistrationFields } from "./ClientAuthFields";
import {
  cleanRegistration,
  registrationError,
  registrationToDraft,
  sameRegistration,
  type RegistrationDraft,
} from "./client-auth-model";

const APPLICATION_CLIENT_AUTH_KEY = "application-client-auth";

interface Draft {
  registration: RegistrationDraft | null;
}

const toDraft = (a: ApplicationClientAuth): Draft => ({
  registration: registrationToDraft(a.registration),
});

const sameDraft = (a: Draft, b: Draft) => sameRegistration(a.registration, b.registration);

/** One application's client auth edit state, for the pane that owns the application's bar. */
export interface ApplicationClientAuthState {
  appId: string | null;
  loaded: ApplicationClientAuth | null;
  draft: Draft | null;
  patch: (next: Partial<Draft>) => void;
  loadError: string | null;
  saveError: string | null;
  generation: number;
  /** The section's edits differ from the server's. */
  dirty: boolean;
  canSave: boolean;
  blockedReason: string | null;
  saving: boolean;
  /** Persist the edits. Resolves false, with `saveError` set, when the write fails — and false
   *  when another application was opened while it was in flight, so nothing chained on it runs
   *  against the application now showing. */
  save: () => Promise<boolean>;
  reset: () => void;
  /** Drop a deleted application's cached client auth, so an application re-created under the
   *  same id loads its own instead of the deleted one's registration. */
  forget: (appId: string) => void;
}

/**
 * The edit state behind an application's "Client auth" section: its login registration, shaped
 * by the application's platform. Who may sign in or sign up is the ecosystem's setting alone.
 * The application's pane owns its one bar (a list pane's `useMasterDetailForm` bar, which
 * DetailsPane uses as-is without consulting sections), so this hands dirty / save / reset back
 * for the pane to fold into that bar rather than registering a section of its own.
 *
 * `appId` null (nothing selected, or a create in progress) loads nothing and is never dirty.
 * Switching applications drops the previous one's edits; the pane's unsaved-work guard has
 * already asked by then.
 */
export function useApplicationClientAuth(appId: string | null): ApplicationClientAuthState {
  const { item: loaded, error: loadError } = useResourceItemQuery<ApplicationClientAuth>(
    APPLICATION_CLIENT_AUTH_KEY,
    appId,
    clientAuthApi.application,
  );
  const writeLoaded = useResourceItemWriter<ApplicationClientAuth>(APPLICATION_CLIENT_AUTH_KEY);

  const draft = useSettingsDraft<ApplicationClientAuth, Draft>(loaded, toDraft, sameDraft);
  // Bumped on every re-seed, so the URL editors' own rows follow the draft back.
  const [generation, setGeneration] = useState(0);
  // The draft also re-seeds on its own when an unedited record moves (a background refetch);
  // the editors keep their own rows, so that re-seed must bump the generation too.
  const [seedSeen, setSeedSeen] = useState(draft.seed);
  if (seedSeen !== draft.seed) {
    setSeedSeen(draft.seed);
    setGeneration((g) => g + 1);
  }
  // The application showing NOW, for a save that resolves after the user has moved on.
  const currentApp = useRef(appId);
  currentApp.current = appId;
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  // A different application: drop the last one's draft. Adjusted during render, React's idiom for
  // state that resets on a prop change, so no frame shows one app's edits over another's record.
  const [draftFor, setDraftFor] = useState(appId);
  if (draftFor !== appId) {
    setDraftFor(appId);
    draft.reset();
    setGeneration((g) => g + 1);
    setSaveError(null);
  }

  // The platform the server holds, since that is what it validates the registration against.
  const blockedReason = draft.draft
    ? registrationError(draft.draft.registration, loaded?.platform)
    : null;

  const reset = () => {
    draft.reset();
    setGeneration((g) => g + 1);
    setSaveError(null);
  };

  const save = async (): Promise<boolean> => {
    const current = draft.draft;
    if (!appId || !current || !draft.dirty) return true;
    setSaving(true);
    setSaveError(null);
    try {
      const updated = await clientAuthApi.updateApplication(appId, {
        registration: current.registration && cleanRegistration(current.registration),
      });
      writeLoaded(appId, updated);
      // Another application opened while this was in flight: its draft is not this one's to
      // commit into.
      if (currentApp.current !== appId) return false;
      draft.commit(updated);
      setGeneration((g) => g + 1);
      return true;
    } catch (err) {
      if (currentApp.current !== appId) return false;
      setSaveError(err instanceof Error ? err.message : "Failed to save client auth.");
      return false;
    } finally {
      setSaving(false);
    }
  };

  return {
    appId,
    loaded: loaded ?? null,
    draft: draft.draft,
    patch: draft.patch,
    loadError,
    saveError,
    generation,
    dirty: appId !== null && draft.dirty,
    canSave: blockedReason === null,
    blockedReason,
    saving,
    save,
    reset,
    forget: (id: string) => writeLoaded(id, null),
  };
}

/**
 * An application's "Client auth" section: its own login registration, a client id separate from
 * the ecosystem's. A web application lists redirect URIs and return origins; a native one lists
 * redirect URIs only. Sign-in and sign-up follow the ecosystem's settings (Users ▸
 * Authentication).
 */
export function ApplicationClientAuthSection({ state }: { state: ApplicationClientAuthState }) {
  const { draft, loaded } = state;
  if (!state.appId) return null;
  if (!draft || !loaded) {
    return (
      <DetailSection title="Client auth">
        <ErrorText error={state.loadError} />
        {!state.loadError && <p className="text-sm text-apt-text-muted">Loading…</p>}
      </DetailSection>
    );
  }
  return (
    <LoginRegistrationFields
      title="Client auth"
      idPrefix="app-client-auth"
      platform={loaded.platform}
      registration={draft.registration}
      clientId={loaded.registration?.clientId ?? null}
      onChange={(registration) => state.patch({ registration })}
      generation={state.generation}
      error={state.saveError}
      emptyText="This application has no login registration. Create one to give it a client id its customers sign in through, under the ecosystem's sign-in settings (Users ▸ Authentication)."
    />
  );
}
