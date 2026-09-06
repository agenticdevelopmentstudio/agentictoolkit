"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2, Plug } from "lucide-react";

import { reportUnexpectedAuthError, useAuth } from "@agentic-toolkit/auth";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { httpStatus } from "@agentic-toolkit/data";
import {
  decodeOAuthStateClaims,
  integrationsApi,
  isOAuthStateFresh,
} from "@agentic-toolkit/data/integrations";
import {
  FALLBACK_RETURN_TO,
  clearPendingConnect,
  consumedReturnTo,
  hasPendingConnect,
  markPendingConnectConsumed,
  readPendingConnect,
  wasPendingConnectConsumed,
  type PendingOAuthConnect,
} from "./oauth-callback-store";

type Phase = "working" | "error" | "done";

/**
 * Where a connect that left the app comes back to. Every site that starts one mounts this
 * at `/integrations/oauth-callback` (OAUTH_CALLBACK_PATH).
 *
 * React state didn't survive the round-trip, so the connect context is recovered from
 * `sessionStorage` (keyed by the signed `state` every flow echoes back), the connect is
 * finished, the entry is cleared, and the visitor is routed back where they started. Query
 * params are read from `window.location` (client-only), so no Suspense boundary is needed.
 *
 * WHAT sits beside the state differs by flow, which is why the stashed context is read
 * before any credential is demanded:
 *   • oauth / oauth_instance → `?code=` — an authorization to exchange for a token.
 *   • github_app            → `?installation_id=&setup_action=` — not an authorization
 *     but a thing that now exists at the provider and has an id. `setup_action=request`
 *     means an org owner still has to approve it, so there is no installation to file yet.
 */
export interface IntegrationsOAuthCallbackProps {
  /**
   * Where to send someone whose return context could not be recovered, and where the Back
   * button goes when there is no address to name.
   *
   * Defaults to {@link FALLBACK_RETURN_TO}, which is the FAMILY's entry point — `/home` plus
   * the connections fragment — because a GitHub App has one Setup URL for the whole app and
   * this component therefore fields arrivals from siblings that share nothing but that
   * convention. A site whose console does not live at `/home`, or which shows its
   * connections somewhere the fragment means nothing, would otherwise land its own operators
   * on a page it never mounted, with no way to say so from the outside. Naming the
   * destination is the host's job because the destination is the host's fact.
   */
  fallbackReturnTo?: string;
}

export function IntegrationsOAuthCallback({
  fallbackReturnTo = FALLBACK_RETURN_TO,
}: IntegrationsOAuthCallbackProps = {}) {
  const router = useRouter();
  const { isLoading, isAuthenticated, user } = useAuth();
  const [phase, setPhase] = useState<Phase>("working");
  const [message, setMessage] = useState("Finishing your connection…");
  const [returnTo, setReturnTo] = useState<string | null>(null);
  const ran = useRef(false);
  // The connect is in-flight across a network round-trip; if the user navigates away before
  // it resolves, don't setState on an unmounted component and — the surprising one — don't
  // router.replace them back here from wherever they went (mirrors the sibling components'
  // `alive` guard).
  const alive = useRef(true);
  useEffect(() => {
    // Re-ARMED, not merely torn down: under StrictMode the effect below runs, is cleaned up,
    // and runs again on the same mount, so a cleanup-only version leaves `alive` false while
    // the one in-flight connect (started by the first run, and not restarted by the second —
    // `ran` sees to that) is still resolving. Both exits then check a flag nothing will ever
    // set back, and the page spins forever. Every sibling with an `alive` ref arms it here.
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  const userId = user?.id;

  useEffect(() => {
    if (ran.current) return;

    // The query is parsed, and every SYNCHRONOUS verdict below is reached, BEFORE `ran` is
    // set. The latch exists to stop the connect happening twice; placed at the top it also
    // swallowed the only thing the dependency array is for — a session that settles after
    // this effect's first pass — which made `isAuthenticated` decorative and parked the
    // operator on "your session isn't active" with no route back but a reload.
    const params = new URLSearchParams(window.location.search);
    const code = params.get("code");
    const installationId = params.get("installation_id");
    const setupAction = params.get("setup_action");
    const state = params.get("state");
    const oauthError = params.get("error");

    const fail = (text: string) => {
      if (!alive.current) return;
      setPhase("error");
      setMessage(text);
    };
    /** A verdict no dependency can overturn — latch, so later passes don't re-litigate it. */
    const settle = (text: string) => {
      ran.current = true;
      fail(text);
    };

    if (oauthError) {
      return settle(`Authorization was cancelled or failed (${oauthError}).`);
    }
    // `state` is checked first and alone: it is the one parameter every flow returns, and
    // the context it keys is what says which credential the rest of the query owed us.
    if (!state) {
      return settle("This callback is missing its round-trip state, so there's nothing to finish.");
    }
    if (wasPendingConnectConsumed(state)) {
      // A reload — or a session restore, or a back-button — onto a callback that already
      // succeeded. The signed state is stateless, with no consumption record anywhere, and
      // the recovery path below rebuilds a context happily from the URL, so without this
      // tombstone the second pass POSTs again and the backend answers 409 "already connected
      // to …". That reached the operator as raw API prose and Sentry as an event, for the
      // ordinary act of refreshing a page that had worked.
      ran.current = true;
      if (alive.current) {
        setPhase("done");
        setMessage("This connection is already set up — nothing left to finish.");
        // The tombstone carries where the connect came from, and this branch is the one place
        // that address exists nowhere else: the stash was cleared when the credential was
        // spent, and the recovery path can only invent the family fallback. Without it the
        // operator who refreshed a page that had already worked is offered a Back button to
        // somebody else's `/home` rather than to the dialog they were standing in.
        const home = consumedReturnTo(state);
        if (home) setReturnTo(home);
      }
      return;
    }

    // Which context finishes this callback — and, just as load-bearing, WHY there isn't one.
    // "Nothing was stashed on this origin" is the ordinary cross-origin arrival that a GitHub
    // App's single Setup URL guarantees, and it is recoverable from the signed state.
    // "Something was stashed and cannot be read" is corruption, and rebuilding over it
    // silently reclassifies the flow: an `oauth` connect has a stash precisely because it has
    // a redirect_uri only the stash carries, so a github_app context invented in its place
    // fails at the provider instead of reporting the stash that is actually broken.
    if (!readPendingConnect(state) && hasPendingConnect(state)) {
      return settle(
        "This connection's saved details are unreadable, so it can't be finished. Start again" +
          " from Integrations.",
      );
    }
    const ctx =
      readPendingConnect(state) ??
      recoverFromState({ state, installationId, setupAction, code, fallbackReturnTo });
    if (!ctx) {
      return settle(
        "This connection link has expired or was already used. Start again from Integrations.",
      );
    }
    if (alive.current) setReturnTo(ctx.returnTo);

    if (isLoading) return; // wait for the session to hydrate before an authed connect
    if (!isAuthenticated) {
      // Deliberately NOT latched. `isLoading` settles false with no user whenever a silent SSO
      // probe is declined or `/auth/me` returns a transient 5xx with nothing cached, and the
      // user object can arrive afterwards. That transition is exactly what this effect's
      // dependencies are for.
      return fail("Your session isn't active. Sign in, then reconnect from Integrations.");
    }

    // The claims name the caller and the moment the flow began, and the backend re-checks
    // both before it writes anything. Answering them here costs nothing and is the difference
    // between a sentence the operator can act on and the backend's own rejection text
    // arriving as an unexpected error — with a Sentry event attached.
    const claims = decodeOAuthStateClaims(state);
    if (claims && !isOAuthStateFresh(claims)) {
      // Not hypothetical, and not an edge: `setup_action=request` tells the operator that an
      // org owner has to approve the install, and an approval that lands after the ten-minute
      // window returns a state the backend is certain to refuse.
      return settle(
        "This connection request has expired. Start again from Integrations to get a fresh one.",
      );
    }
    if (claims && userId && claims.customerId !== userId) {
      // Unlatched for the same reason as the sign-in message above: signing in as the account
      // that started the flow is a thing the operator can do from here, and `userId` is in the
      // dependency array so that it takes effect.
      return fail(
        "This connection was started from a different account. Sign in as that account, or" +
          " start again from Integrations.",
      );
    }

    ran.current = true;
    // A pass that reached here after an earlier one reported something recoverable — no
    // session yet, the wrong account — must not leave that message standing over a connect
    // that is now actually running.
    if (alive.current) {
      setPhase("working");
      setMessage("Finishing your connection…");
    }

    void (async () => {
      // Whether the credential was actually SPENT — i.e. whether the BACKEND SAW IT — which is
      // the only thing that makes the stash safe to destroy. See the `finally`.
      //
      // It is therefore set from what came back, never before the call: a rejection with no
      // numeric status never reached the backend at all (offline, DNS, a dropped connection,
      // CORS), so the installation is still unfiled and the credential is still good. Setting
      // it beforehand destroyed the stash on exactly those failures, and the retry the error
      // message invites then reports an expired link — `redirectUri` lives nowhere but the
      // stash, and nothing can invent one. Which statuses count is `consumesCredential`'s
      // question, not "any status at all" — see it for why a 503 is the same situation as a
      // dropped connection wearing a number.
      let spent = false;
      try {
        const missing = (what: string) =>
          fail(`This callback is missing its ${what}, so there's nothing to finish.`);

        if (ctx.authMethod === "github_app") {
          if (setupAction === "request") {
            return fail(
              "You asked for the app to be installed on that organization, and an owner has to" +
                " approve it. Connect again once they have.",
            );
          }
          if (!installationId) return missing("installation id");
          await integrationsApi.connect({
            type: "github_app",
            providerId: ctx.providerId,
            serviceType: ctx.serviceType,
            ecosystemId: ctx.ecosystemId,
            installationId,
            state,
          });
        } else if (!code) {
          return missing("authorization code");
        } else if (ctx.authMethod === "oauth") {
          await integrationsApi.connect({
            type: "oauth",
            providerId: ctx.providerId,
            serviceType: ctx.serviceType,
            ecosystemId: ctx.ecosystemId,
            code,
            redirectUri: ctx.redirectUri,
            state,
          });
        } else {
          await integrationsApi.connect({
            type: "oauth_instance",
            providerId: ctx.providerId,
            serviceType: ctx.serviceType,
            ecosystemId: ctx.ecosystemId,
            code,
            state,
          });
        }
        spent = true;
        // The tombstone goes down only on a connect that SUCCEEDED: a failed one leaves
        // nothing filed at the provider's end of this app, so a retry is the right answer and
        // must not be met with "already set up".
        markPendingConnectConsumed(state, ctx.returnTo);
        if (alive.current) router.replace(ctx.returnTo);
      } catch (err) {
        // Never DOWNgraded: the success path has already set it before anything that can
        // throw after the connect returned, and such a throw is not evidence the credential
        // went unspent.
        spent = spent || consumesCredential(httpStatus(err));
        if (isAlreadyConnectedConflict(err, ctx.providerId)) {
          // The connect that this callback was going to make has ALREADY HAPPENED, and
          // succeeded — this document just is not the one that made it. Two tabs on the same
          // callback URL is the ordinary way to get here (Duplicate Tab clones
          // `sessionStorage`, so the loser sees no tombstone), and a session restore that
          // reopens the tab alongside a live one is the other.
          //
          // Reported as the outcome it is rather than as the backend's own prose, which named
          // an internal provider id at an operator whose connection is, in fact, set up. The
          // tombstone goes down so a further reload of THIS document recognizes itself, and
          // nothing navigates: the tab that won the race is doing that, and two documents
          // racing to `router.replace` the same address is how one of them loses a scroll
          // position for no reason.
          spent = true;
          markPendingConnectConsumed(state, ctx.returnTo);
          if (alive.current) {
            setPhase("done");
            setMessage("This connection is already set up — nothing left to finish.");
          }
          return;
        }
        reportUnexpectedAuthError(err, {
          feature: "integration-oauth-callback",
          step: ctx.authMethod,
        });
        fail(err instanceof Error && err.message ? err.message : "Couldn't finish the connection.");
      } finally {
        // Cleared on the exits that spent the credential, and ONLY those. The four above it
        // consume nothing — an approval still pending, a missing installation id, a missing
        // code, and (before the async even starts) no session — and every one of them tells
        // the operator to try again from here. A blanket clear took the stash away on all
        // four, so the retry the message invited then reported an expired link: `redirectUri`
        // exists nowhere but the stash, and the recovery path cannot invent one.
        if (spent) {
          // The tombstone goes down BEFORE the stash goes away, and on every spending exit
          // rather than only on the two that file one of their own. After
          // `clearPendingConnect` there is nothing left for a reload of this document to
          // recognize itself by — the state is out of the stash and unspendable at the
          // backend — so a spent-but-untombstoned replay reports "expired or was already
          // used" as if the link had never worked, for a credential that was in fact
          // redeemed. The tombstone is what turns that into the true sentence, and it
          // carries `returnTo` so the replay lands where the operator started rather than on
          // the family fallback. A plain overwrite, so the success and already-connected
          // paths filing it first costs nothing.
          markPendingConnectConsumed(state, ctx.returnTo);
          clearPendingConnect(state);
        }
      }
    })();
  }, [isLoading, isAuthenticated, userId, router, fallbackReturnTo]);

  return (
    <div className="flex min-h-[60vh] items-center justify-center px-6 py-16">
      {/* ONE live region, spanning every phase, because the announcement that matters is the
          TRANSITION out of "Finishing your connection…" — and a region mounted only on the
          working branch is unmounted at the exact moment there is something to say. A screen
          reader then hears the spinner's message and never hears the outcome; the page simply
          goes quiet, on a route whose entire content is that outcome. Politeness rises with
          the phase: a failure interrupts, because it is the one state that asks the operator
          to do something and the one they can otherwise sit in indefinitely. */}
      <div
        className="flex w-full max-w-md flex-col items-center gap-4 rounded-lg border border-apt-border bg-apt-surface p-8 text-center"
        role="status"
        aria-live={phase === "error" ? "assertive" : "polite"}
        aria-atomic="true"
      >
        <Plug className="size-6 text-apt-gold" aria-hidden />
        {phase === "working" ? (
          <div className="flex flex-col items-center gap-3">
            <Loader2 className="size-5 animate-spin text-apt-text-muted" aria-hidden />
            <p className="text-sm text-apt-text-muted">{message}</p>
          </div>
        ) : (
          <div className="flex flex-col items-center gap-4">
            {/* The heading names the OUTCOME, and a replay is not a failure: a refreshed
                callback that already succeeded said "Connection not completed" over a
                connection that was, in fact, completed — which is the one reading that makes
                an operator start the whole flow again. */}
            {/* Told apart by more than the words: "Already connected" and "Connection not
                completed" are the same shape, the same weight and the same colour, so the two
                outcomes are one glance apart for anyone who reads the layout before the
                sentence. Only the failure is coloured — a success that shouted would be the
                same mistake in the other direction. */}
            <h1
              className={
                phase === "done"
                  ? "text-base font-semibold text-apt-text"
                  : "text-base font-semibold text-apt-red"
              }
            >
              {phase === "done" ? "Already connected" : "Connection not completed"}
            </h1>
            <p className="text-sm text-apt-text-muted">{message}</p>
            {/* "Back", not "Back to Integrations": where this lands is whatever URL the visitor
                left from, which on a console that shows connections in a DIALOG is a workspace
                page, not a page called Integrations. Naming a destination the button may not
                have is worse than naming none. */}
            <Button onClick={() => router.replace(returnTo ?? fallbackReturnTo)}>Back</Button>
          </div>
        )}
      </div>
    </div>
  );
}

/**
 * Rebuild a `github_app` context from the `state` alone, for the return that arrives on an
 * origin that never stashed one.
 *
 * A GitHub App has ONE Setup URL for the whole app, so an installation started anywhere in
 * the family comes back to that single origin — while the stash is `sessionStorage`, which is
 * per-origin and therefore empty there. Without this, "connect" on any site but the one
 * holding the Setup URL ends on "this link has expired", every time, with nothing wrong.
 *
 * Only `github_app` can be rebuilt: it is the one method that needs no `redirect_uri` to echo,
 * and the one whose credential is an id rather than a single-use code.
 *
 * `returnTo` is the one thing the state cannot carry, so it falls back to the address the
 * host named — by default the family entry point WITH the connections fragment, because this
 * is the arrival the fragment was added for: the operator started the connect from a dialog
 * on another origin, and landing them on a bare tree with every dialog shut is the exact
 * symptom that reads as the connect having failed.
 */
function recoverFromState(params: {
  state: string;
  installationId: string | null;
  setupAction: string | null;
  code: string | null;
  fallbackReturnTo: string;
}): PendingOAuthConnect | null {
  const { state, installationId, setupAction, code, fallbackReturnTo } = params;
  // A `code` present means an OAuth authorization came back, and the OAuth pair is precisely
  // what cannot be rebuilt: the token exchange must echo the exact `redirect_uri` that was
  // sent, and that lives only in the stash. Refusing here also closes a misroute — the claims
  // name no auth method at all, and `installation_id` is an unsigned query parameter, so
  // without this a genuine `oauth` state paired with an arbitrary `?installation_id=` would be
  // rebuilt as a github_app connect against an OAuth provider.
  if (code) return null;
  // `setup_action` on its own is enough, and has to be: `setup_action=request` — an org owner
  // has yet to approve the install — arrives with NO `installation_id`, and it is a return to
  // the app-wide Setup URL, i.e. exactly the arrival this function exists for. Requiring an id
  // here reported that case as an expired link on the one origin the recovery was written for,
  // with the approval message it needed sitting unreachable inside the branch below.
  if (!installationId && !setupAction) return null;
  const claims = decodeOAuthStateClaims(state);
  if (!claims) return null;
  return {
    authMethod: "github_app",
    providerId: claims.providerId,
    serviceType: claims.serviceType,
    ecosystemId: claims.ecosystemId,
    returnTo: fallbackReturnTo,
  };
}

/**
 * The ONE 409 from `POST /integrations/connect` that means the operator got what they came
 * for. The backend throws two, and they want opposite screens:
 *
 *   • `already connected to '<providerId>' (<serviceType>)` — an earlier connect for THIS
 *     provider succeeded. The work is done; saying so is the whole point.
 *   • `installation <id> is already connected elsewhere; disconnect it there first` — a
 *     genuine refusal, naming a step only the operator can take. Reporting that as success
 *     would leave them believing a connection exists that does not.
 *
 * Both contain the substring "already connected", so the provider id is what tells them
 * apart — and matching the id keeps this from ever widening to the second: the message that
 * refuses names an INSTALLATION id there, never the provider. This is prose coupling to
 * another repo, and it is written to fail in the safe direction: if the backend rewords its
 * conflict, this stops matching and the operator is back to seeing the raw 409 — which is
 * exactly where they were before this existed. The alternative, a broad "already connected"
 * match, fails the other way.
 */
/**
 * Whether a failed connect actually redeemed the one-shot credential — the only thing that
 * makes the state safe to burn and the stash safe to destroy.
 *
 * This used to be "any status at all", on the reasoning that a response means the backend read
 * the credential. It does not. `httpStatus` is `undefined` only for a rejection that never
 * became a response — offline, DNS, a dropped connection, CORS — and a 502 from a proxy in
 * front of the backend, a 503 while it restarts, a 504 on a slow provider exchange and a 500
 * from a handler that threw on its first line are all of them numbers on the same situation:
 * nothing was filed, and the credential is still good. Burning the state on one of those made
 * the retry the error UI invites impossible — the state was spent and the stash cleared, so
 * the retry failed the freshness/stash guard instead of replaying, and the only way forward
 * was to start the whole flow again at the provider. 408 and 429 are the same answer for the
 * same reason: both mean "not now", not "not again".
 *
 * The asymmetry is deliberate and it is the safe direction. Guessing "unspent" for a connect
 * that did write costs a retry that meets a 409, which `isAlreadyConnectedConflict` below
 * already turns into "this connection is already set up". Guessing "spent" for one that did
 * not costs the operator the entire flow.
 */
function consumesCredential(status: number | undefined): boolean {
  if (status === undefined) return false;
  if (status === 408 || status === 429) return false;
  return status < 500;
}

function isAlreadyConnectedConflict(err: unknown, providerId: string): boolean {
  if (httpStatus(err) !== 409) return false;
  const message = err instanceof Error ? err.message : "";
  return message.includes(`already connected to '${providerId}'`);
}
