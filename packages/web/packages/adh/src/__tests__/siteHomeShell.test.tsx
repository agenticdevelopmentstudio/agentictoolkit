import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useState } from "react";
import type { SiteId } from "@agentic-toolkit/adh-registry";
import {
  render,
  screen,
  waitFor,
  cleanup,
  configure,
  fireEvent,
  act,
  within,
} from "@testing-library/react";

// Every wait in this file is for a MICROTASK chain — the router double's deferred `liveSetSlug`,
// then React's render and effects — so the real settle is sub-millisecond and the timeout is pure
// headroom. testing-library's 1000ms default is not enough headroom here: `pnpm test` runs 59 jsdom
// environments in parallel, and one full-suite run timed out at line ~1002 waiting for a write that
// passes in 2ms standalone. Raising the ceiling costs a green run nothing (a satisfied wait returns
// on its next 50ms poll either way) and only changes how long a genuinely broken one takes to fail.
// Scoped to this file rather than the shared root setup, which every package's tests load.
configure({ asyncUtilTimeout: 5000 });

// A STATEFUL router double. `replace`/`push` both record the call (so assertions can still
// check what was requested) AND move a live slug the way the App Router actually does — unlike
// a bare vi.fn(), which lets `workspaceSlug` stay frozen no matter how many times the shell
// calls it. A frozen prop hides exactly the bug this file exists to catch: the shell writing its
// own guess into the URL and then reading that guess back as top-priority truth. See
// `liveSetSlug` below and review round 1, finding 3.
//
// The slug update is deferred a microtask rather than applied synchronously: the real App
// Router updates the URL param on a LATER render than the one that called push/replace, not the
// same one. That gap is exactly what finding 2 is about — a synchronous update would let
// `setStored` (old code) and the URL change land in the same React batch and never expose the
// half-state where the URL still names the old workspace while `stored` already names the new
// one. `Promise.resolve().then(...)` reproduces that ordering without a real timer.
let liveSetSlug: (slug: string | undefined) => void = () => {};
// The workspace segment is the FIRST one, on every site — which is the only way to read it now
// that a switch carries the segments BELOW it (`/acme/services/s_1`). The last segment used to be
// the slug and no longer is; taking `.pop()` here would have fed the deepest entity id back as
// `workspaceSlug` and made a carrying test pass for the wrong reason.
// The query and the fragment are stripped first, because they are not part of any segment. The
// real router parses the href into a path plus a search plus a hash, and `params.workspace` is a
// path segment — feeding `acme?invite=1` back as the slug would make the shell 404 its own
// redirect. Same reason `usePathname()` below is set from the path alone.
const extractSlug = (href: string): string =>
  href.split(/[?#]/)[0]!.split("/").filter(Boolean)[0]!;
const extractPathname = (href: string): string => href.split(/[?#]/)[0]!;

// What `usePathname()` answers. A module variable rather than state because nothing re-renders on
// it alone: the shell reads it only when building the href for a click, and the render that follows
// a `push` is driven by `liveSetSlug` in the same microtask. Defaults to "" (reset in `beforeEach`)
// — the shell reads no segments below the workspace out of that, so every case that predates the
// carry behaves exactly as it did. A case that IS about the carry sets it to the deep URL it means.
let livePathname = "";

// Whether the double feeds its href back into `workspaceSlug` at all. Normally it does. A test
// switches it off to hold the URL STILL after the shell has already resolved — the window the
// real router leaves open between `replace()` being called and the route re-rendering with the
// new param. One microtask is too short to observe from a test; this makes that window explicit.
let routerFeedsBack = true;
const replace = vi.fn((href: string) => {
  if (!routerFeedsBack) return;
  void Promise.resolve().then(() => {
    livePathname = extractPathname(href);
    liveSetSlug(extractSlug(href));
  });
});
const push = vi.fn((href: string) => {
  if (!routerFeedsBack) return;
  void Promise.resolve().then(() => {
    livePathname = extractPathname(href);
    liveSetSlug(extractSlug(href));
  });
});
// ONE router object for the whole file, not a fresh literal per `useRouter()` call. The real App
// Router hands back a stable instance out of context; a per-render literal is a strictly WEAKER
// double, because `router` is in the replace effect's dependency array — a new identity every
// render re-runs that effect every render, which silently supplies the re-runs a missing
// dependency should have cost. Measured: with a per-render literal, dropping `workspaceSlug`
// from that array left the WHOLE file green (round 5 matrix, row v04; re-measured at the shipped
// 37 tests); with this stable object the same mutation is red. Same reasoning as round 1's
// frozen-prop finding — a double that is more generous than production certifies code production
// would break. This is not merely "stable enough": in the Next this package resolves,
// `useRouter()` is a bare `useContext(AppRouterContext)` whose provider value is a module-level
// const, so production returns the SAME object across every render, mount and route change —
// exactly what this object does. Neither more nor less generous.
const routerDouble = { replace, push, prefetch: vi.fn() };
// No `notFound` mock: `SiteHomeShell` no longer imports it (an unreachable workspace slug renders
// `ProfileFallback` instead — see the guard comment in SiteHomeShell.tsx), so a double for it would
// stand for nothing this file exercises. `SiteHomeModel.ts` still calls `notFound()` on its own
// path-length check, but that module is only ever a type-only import from here.
vi.mock("next/navigation", () => ({
  useRouter: () => routerDouble,
  usePathname: () => livePathname,
}));

const list = vi.fn();
const prefsGet = vi.fn();
const prefsPut = vi.fn();
const readCached = vi.fn();
const writeCached = vi.fn();

// `put`'s RETURN VALUE is produced by this plain function, not by `prefsPut` itself. A vi.fn()
// attaches its own `.then`/`.catch` to whatever promise it returns, to record the settled value
// in `mock.results` — and that attachment counts as "handling" the rejection before Node's
// microtask queue would otherwise call it unhandled. So a promise built with
// `prefsPut.mockRejectedValue(...)` and left uncaught never reaches `process.on("unhandledRejection")`
// — confirmed empirically with two standalone probes (a bare `Promise.reject` fires the event;
// the identical rejection returned from ANY vi.fn(), via `mockRejectedValue` or
// `mockImplementation`, does not). `prefsPut` still records every call for the `toHaveBeenCalledWith`
// assertions below; only the settled promise itself is routed around it.
let prefsPutResult: () => Promise<void> = () => Promise.resolve();

// What the real hook's module-scope cache would have seeded this mount with. Null — a cold cache —
// for every test but the one that needs rows ALREADY on screen when a request fails; see
// use-resource-list.ts's "the cache seeds the first paint … this is the authoritative read that
// settles behind it". Reset in `beforeEach`.
let seedRows: unknown[] | null = null;

// Records the shell's write-through of a chosen workspace into the shared item cache. Module
// scope so `useResourceItemWriter`'s stub can hand back ONE stable identity — the real hook's is
// a `useCallback`, and the persistence effect holds it in a dependency array.
const itemWrite = vi.fn();

// The whole data boundary is mocked, `useResourceList` and `useResourceItemQuery` INCLUDED. The
// real hooks cache at MODULE scope keyed by cacheKey, and every mount in the family now uses the
// same literal key — so the second test would seed from the first one's rows and the "holds
// children" case could never observe a null list, and every per-mount `prefsGet` count below would
// stop meaning anything the moment one test's answer outlived it. The stubs are the hooks'
// contract with that cache made EXPLICIT instead of implicit: `seedRows` above stands in for it,
// so a test says which state it is starting from rather than inheriting one from whichever test
// ran before it. What the cache BUYS is asserted next door, in workspacePrefsCache.test.tsx,
// against the real hook. (Async factory because vi.mock is hoisted above the imports, so React has
// to be pulled in here rather than referenced from module scope.)
vi.mock("@agentic-toolkit/data", async () => {
  const { useEffect, useState } = await import("react");
  return {
    useResourceList: (_cacheKey: string, load: () => Promise<unknown[]>) => {
      const [items, setItems] = useState<unknown[] | null>(seedRows);
      // The failure half of the contract, mirrored exactly (use-resource-list.ts:126-129): a
      // rejection sets `error` and leaves `items` UNTOUCHED — null on a cold mount, the previous
      // rows on a failed reload. A stub that nulled the rows instead would hide the only thing
      // that makes the shell's error branch necessary: a null list and a failed list look
      // identical from `items` alone.
      const [error, setError] = useState<string | null>(null);
      // Starts TRUE and is cleared by whichever path settles, exactly as the real hook does
      // (use-resource-list.ts). It is the rung that keeps a SEEDED first render from reading as
      // the server's answer, so a stub that hardcoded `false` would make the one test that seeds
      // rows pass for the wrong reason — and one that hardcoded `true` would disable the profile
      // branch entirely, which a good part of this file asserts.
      const [isFetching, setIsFetching] = useState(true);
      // `_cacheKey` is a dependency here for the same reason it is one in the real hook
      // (use-resource-list.ts:133): a changed key is a different collection, and it refetches.
      // Nothing in the family changes it any more — one workspace list, one literal key — but the
      // stub mirrors the hook rather than the current callers, so it keeps saying so.
      useEffect(() => {
        let alive = true;
        setIsFetching(true);
        void load()
          .then((rows) => {
            if (alive) {
              setError(null);
              setItems(rows);
              setIsFetching(false);
            }
          })
          .catch((e: unknown) => {
            if (alive) {
              setError(e instanceof Error ? e.message : "Failed to load.");
              setIsFetching(false);
            }
          });
        return () => {
          alive = false;
        };
      }, [load, _cacheKey]);
      return { items, reload: vi.fn(), error, isFetching, setItems };
    },
    // The item hook, mirrored on the same terms as the list hook above — one read per mount, no
    // cache between them, so a case that mounts twice still gets the two `prefsGet` calls its
    // `mockReturnValueOnce` pair is written for. `item` stays null until the read lands (the real
    // hook's `query.data ?? null`) and a failure leaves it null while setting `error`, which is
    // exactly the pair `useWorkspaceRoute` derives "the read has answered" from.
    useResourceItemQuery: (
      _cacheKey: string,
      id: string | null,
      load: (id: string) => Promise<unknown>,
    ) => {
      const [item, setItem] = useState<unknown>(null);
      const [error, setError] = useState<string | null>(null);
      useEffect(() => {
        if (id == null) return;
        let alive = true;
        void load(id)
          .then((value) => {
            if (alive) {
              setError(null);
              setItem(value);
            }
          })
          .catch((e: unknown) => {
            if (alive) setError(e instanceof Error ? e.message : "Failed to load.");
          });
        return () => {
          alive = false;
        };
      }, [load, id, _cacheKey]);
      return {
        item,
        isSettled: id == null || item !== null || error !== null,
        isFetching: id != null && item === null && error === null,
        error,
        reload: vi.fn(),
        isMissing: false,
      };
    },
    useResourceItemWriter: () => itemWrite,
    workspacesApi: { list: () => list() },
    workspacePrefsApi: {
      get: () => prefsGet(),
      put: (p: unknown) => {
        prefsPut(p);
        return prefsPutResult();
      },
    },
    readCachedWorkspace: () => readCached(),
    writeCachedWorkspace: (s: string) => writeCached(s),
  };
});

// The picker is stubbed too. This file is about WHICH workspace the shell resolves and WHEN it
// mounts its children; the real picker's trigger is a Base UI menu whose open/close needs
// pointer plumbing and @testing-library/user-event, which is not a devDependency here. The
// picker's own props are covered by workspacePicker.test.tsx next door.
vi.mock("../home/WorkspacePicker", () => ({
  WorkspacePicker: ({
    workspaces,
    selected,
    onSelect,
  }: {
    workspaces: { slug: string; name: string }[] | null;
    selected: string | null;
    onSelect: (slug: string) => void;
  }) => (
    <div data-testid="picker" data-selected={selected ?? "none"}>
      {(workspaces ?? []).map((w) => (
        <button key={w.slug} type="button" onClick={() => onSelect(w.slug)}>
          {w.name}
        </button>
      ))}
    </div>
  ),
}));

// Stubbed for the same reason the picker is: this file is about WHICH slug (and site) the shell
// hands the fallback, not how a profile itself renders — that is ProfileFallback's own concern.
// Captured via data attributes, matching the picker mock's convention above, rather than a
// hoisted ref: this file has no other hoisted-capture mocks and there is no ordering reason to
// start one here.
vi.mock("../profile/ProfileFallback", () => ({
  ProfileFallback: ({ slug, siteId }: { slug: string; siteId: string }) => (
    <div data-testid="profile-fallback" data-slug={slug} data-site-id={siteId}>
      profile fallback
    </div>
  ),
}));

const { SiteHomeShell } = await import("../home/SiteHomeShell");
// The seed marker the shell's hook writes before redirecting is a MODULE variable — deliberately,
// because the redirect it records crosses a route boundary and nothing inside the tree survives
// that. A module variable also outlives a test's unmount, so the marker one case leaves behind
// would be read by the next case's mount as if that case had seeded it (measured: it turned the
// deep-link case's one PUT into zero). `beforeEach` resets it, which is the same thing a browser
// does on a full page load.
const { __resetSeededWorkspace } = await import("../home/useWorkspaceRoute");
// Real, unmocked: the profile branch throws without it (see SiteHomeShell.tsx's `siteId === null`
// guard), because every real mount that can reach that branch is inside the `[workspace]` layout,
// which mounts this provider. Used only by the cases below that reach the profile branch, or that
// pin a rung guarding it — never by `/home`, which the shell's own doc comment says mounts with no
// provider at all.
const { SiteIdProvider } = await import("../site/site-id");

const WORKSPACES = [
  { slug: "mine", name: "My Workspace", kind: "individual" as const },
  { slug: "acme", name: "Acme", kind: "organization" as const },
];

/** Live-URL harness. Holds the slug the shell sees in state and feeds it back to
 * `workspaceSlug` — `replace`/`push` above update that state, so a test can observe the shell's
 * FINAL landing after a full async resolution + redirect cycle, not just the first call a mock
 * recorded. The assignment happens in the render body (not an effect): Harness's function body
 * always runs before its child's, so by the time SiteHomeShell mounts and its effects can call
 * `replace`/`push`, `liveSetSlug` already points at this instance's setter. */
function Shell({
  workspaceSlug,
  workspaceHref,
}: {
  workspaceSlug?: string;
  workspaceHref?: (slug: string) => string;
}) {
  const [slug, setSlug] = useState<string | undefined>(workspaceSlug);
  liveSetSlug = setSlug;
  return (
    <SiteHomeShell workspaceSlug={slug} workspaceHref={workspaceHref}>
      {/* The scope is rendered, not just consumed, so every test in this file that waits for
          `feature` is also asserting the shell never calls its child with a half-resolved one:
          `scopedBase` here is whatever the shell built, and the dedicated test below reads it. */}
      {({ workspaceSlug: ws, scopedBase, workspace }) => (
        <div
          data-testid="feature"
          data-workspace={ws}
          data-scoped-base={scopedBase}
          data-kind={workspace.kind}
        >
          the feature
        </div>
      )}
    </SiteHomeShell>
  );
}

/** `<Shell>` inside the provider every real mount that can reach the profile branch has: the
 *  `[workspace]` layout mounts `SiteIdProvider` above `SiteHomeShell`, and that branch throws
 *  without one (see the shell's `siteId === null` guard). Used by the cases below that land on
 *  the profile, or that pin one of the rungs guarding it — never by `/home`, which the shell's own
 *  doc comment says mounts with no provider at all, and one of those cases asserts exactly that.
 *  `siteId` defaults to the hub because that is what most cases here are about; the override lets
 *  one case mount a different site so it can prove the id is READ off the provider, not assumed. */
function renderReachable(props: { workspaceSlug?: string }, siteId: SiteId = "hub") {
  return render(
    <SiteIdProvider siteId={siteId}>
      <Shell {...props} />
    </SiteIdProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  __resetSeededWorkspace();
  liveSetSlug = () => {};
  seedRows = null;
  livePathname = "";
  routerFeedsBack = true;
  // jsdom's address bar is per-FILE, not per-test, and the seeding redirect now reads
  // `window.location` off it — so a case that sets a query would otherwise hand its query to
  // every case that runs after it.
  window.history.replaceState({}, "", "/");
  list.mockResolvedValue(WORKSPACES);
  prefsGet.mockResolvedValue({});
  prefsPutResult = () => Promise.resolve();
  readCached.mockReturnValue(null);
});
afterEach(cleanup);

// Every row below is a scenario from review round 1, finding 0's table. Two are the load-bearing
// regression tests named in finding 3 — "list lands first, cold cache, server says acme" for
// finding 1, and "user picks acme from mine" for finding 2 — proven red against the pre-fix file
// and green against this one; see the fix report appended to task-6-report.md for that evidence.
describe("SiteHomeShell resolution", () => {
  it("holds children until a workspace is resolved, so no feature mounts unscoped", async () => {
    let settleList: (w: typeof WORKSPACES) => void = () => {};
    list.mockReturnValue(new Promise((r) => (settleList = r)));
    render(<Shell />);
    expect(screen.queryByTestId("feature")).toBeNull();
    // [round 2, finding 3] an assertion used to sit here re-checking `feature` was still absent
    // in the same tick as `settleList` — but resolution happens on a microtask, so nothing could
    // have rendered yet regardless of the code under test; the check could never fail. Dropped —
    // the trailing `waitFor` below is what actually exercises the resolve-then-land path.
    settleList(WORKSPACES);
    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
  });

  it("[finding 1 regression] list lands first, cold cache, server says acme — lands on acme with zero PUTs", async () => {
    readCached.mockReturnValue(null);
    let settleList: (w: typeof WORKSPACES) => void = () => {};
    list.mockReturnValue(new Promise((r) => (settleList = r)));
    let settlePrefs: (p: { slug?: string }) => void = () => {};
    prefsGet.mockReturnValue(new Promise((r) => (settlePrefs = r)));

    render(<Shell />);
    settleList(WORKSPACES);
    // The list has landed but prefs have not — the shell must not have guessed yet. This is the
    // exact half-state the old code got wrong: it resolved to "mine" here, wrote it into the
    // URL, and the server's answer below could never displace it again.
    await waitFor(() => expect(screen.getByRole("button", { name: "Acme" })).toBeInTheDocument());
    expect(replace).not.toHaveBeenCalled();
    expect(prefsPut).not.toHaveBeenCalled();

    settlePrefs({ slug: "acme" });
    await waitFor(() => expect(replace).toHaveBeenCalledWith("/acme", { scroll: false }));
    expect(prefsPut).not.toHaveBeenCalled();
  });

  it("list lands first, warm cache says mine, server says acme — lands on acme with zero PUTs", async () => {
    readCached.mockReturnValue("mine");
    let settlePrefs: (p: { slug?: string }) => void = () => {};
    prefsGet.mockReturnValue(new Promise((r) => (settlePrefs = r)));

    render(<Shell />);
    await waitFor(() => expect(screen.getByRole("button", { name: "Acme" })).toBeInTheDocument());
    // The warm cache alone must not be enough to commit while the server's answer is pending.
    expect(replace).not.toHaveBeenCalled();
    expect(prefsPut).not.toHaveBeenCalled();

    settlePrefs({ slug: "acme" });
    await waitFor(() => expect(replace).toHaveBeenCalledWith("/acme", { scroll: false }));
    expect(replace).toHaveBeenCalledTimes(1);
    expect(prefsPut).not.toHaveBeenCalled();
  });

  it("[round 2] prefs land first, nothing stored — lands on the personal workspace with zero PUTs", async () => {
    // [round 2, finding 2] this used to assert exactly one PUT here — the shell wrote the
    // personal-workspace SEED back to the server. That is the bug: a slug the shell only
    // guessed must never be persisted, only displayed. The spec's "if there isn't a saved
    // workspace default to the user's workspace" makes the personal workspace a fallback for
    // DISPLAY, not something that becomes saved.
    readCached.mockReturnValue(null);
    prefsGet.mockResolvedValue({}); // settles almost immediately; nothing stored
    let settleList: (w: typeof WORKSPACES) => void = () => {};
    list.mockReturnValue(new Promise((r) => (settleList = r)));

    render(<Shell />);
    // Give prefs a tick to settle before the list does — resolution still needs BOTH inputs.
    await new Promise((r) => setTimeout(r, 0));
    expect(replace).not.toHaveBeenCalled();

    settleList(WORKSPACES);
    await waitFor(() => expect(replace).toHaveBeenCalledWith("/mine", { scroll: false }));
    // Give the persistence effect a further tick to fire before asserting it stayed silent.
    await new Promise((r) => setTimeout(r, 0));
    expect(prefsPut).not.toHaveBeenCalled();
    expect(writeCached).not.toHaveBeenCalled();
  });

  it("prefs GET rejects, warm cache says acme — lands on acme with zero PUTs", async () => {
    readCached.mockReturnValue("acme");
    prefsGet.mockRejectedValue(new Error("offline"));
    render(<Shell />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith("/acme", { scroll: false }));
    expect(prefsPut).not.toHaveBeenCalled();
  });

  it(
    "[round 2, finding 2 regression] prefs GET rejects, cold cache — lands on the personal " +
      "workspace for display, but the unread server row survives (zero PUTs)",
    async () => {
      // Nothing in localStorage, and the prefs GET fails — so the shell cannot know what the
      // server actually holds. It still has to land somewhere (the personal workspace, for
      // display), but it must NOT write that guess back: a server row a request merely failed to
      // read is not the same as "nothing saved," and overwriting it would silently destroy
      // whatever workspace the user actually had chosen there.
      readCached.mockReturnValue(null);
      prefsGet.mockRejectedValue(new Error("offline"));
      render(<Shell />);
      await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
      // Give the persistence effect a further tick to fire before asserting it stayed silent.
      await new Promise((r) => setTimeout(r, 0));
      expect(prefsPut).not.toHaveBeenCalled();
      expect(writeCached).not.toHaveBeenCalled();
    },
  );

  it(
    "[round 2, finding 1 regression] prefs GET never settles — after the bail timeout, lands " +
      "on the personal workspace with zero PUTs, and the route does not wedge",
    async () => {
      // A dropped connection or a proxy holding the socket resolves neither `.then` nor `.catch`
      // — before the round-2 fix, `prefsSettled` never flipped and the route rendered nothing
      // below the picker, forever. The bail timeout bounds that wait; the pendingWrite gate (the
      // test above) is what makes bounding it SAFE, since the forced settle can only ever affect
      // what's displayed, never what's written.
      vi.useFakeTimers();
      try {
        readCached.mockReturnValue(null);
        prefsGet.mockReturnValue(new Promise(() => {})); // never settles
        render(<Shell />);
        expect(screen.queryByTestId("feature")).toBeNull();

        // Flushes the 5s bail timer; wrapped in `act` so the chain of renders it triggers
        // (prefsSettled → resolved → replace → the harness's deferred liveSetSlug → another
        // render) is flushed rather than left pending outside React's test instrumentation.
        await act(async () => {
          await vi.advanceTimersByTimeAsync(5000);
        });

        expect(replace).toHaveBeenCalledWith("/mine", { scroll: false });
        expect(screen.getByTestId("feature")).toBeInTheDocument();
        expect(prefsPut).not.toHaveBeenCalled();
        expect(writeCached).not.toHaveBeenCalled();
      } finally {
        vi.useRealTimers();
      }
    },
  );

  it(
    "[final review, parked p03] pins the bail at exactly 5000ms, not merely \"some finite " +
      "number\"",
    async () => {
      // The Task 6 mutation matrix recorded p03 (the `5000` bail, since extracted with the rest
      // of the resolution into useWorkspaceRoute.ts:126-132, which this shell mounts) as
      // pinned only in the sense of "some finite number". Verified empirically against this
      // test in isolation: mutating 5000 → 30000 fails the AFTER assertion below (the bail
      // hasn't actually fired by the true 5000ms mark, so `replace` is never called); mutating
      // 5000 → 3000 fails the BEFORE assertion (it has already fired by 4999ms). Each bound
      // alone only proves an inequality — "no later than 5000ms" or "no earlier than 5000ms" —
      // together they pin the exact number.
      vi.useFakeTimers();
      try {
        readCached.mockReturnValue(null);
        prefsGet.mockReturnValue(new Promise(() => {})); // never settles
        render(<Shell />);

        await act(async () => {
          await vi.advanceTimersByTimeAsync(4999);
        });
        expect(screen.queryByTestId("feature")).toBeNull();
        expect(replace).not.toHaveBeenCalled();

        await act(async () => {
          await vi.advanceTimersByTimeAsync(1);
        });
        expect(replace).toHaveBeenCalledWith("/mine", { scroll: false });
        expect(screen.getByTestId("feature")).toBeInTheDocument();
      } finally {
        vi.useRealTimers();
      }
    },
  );

  it(
    "[round 3, finding 2 regression] the bail timer is cleared once the GET settles normally " +
      "— zero armed timers, not one left ticking for up to 5s",
    async () => {
      // `clearTimeout(bail)` used to run only in the unmount cleanup, so after a NORMAL settle
      // the 5s timer stayed armed and fired a redundant `setPrefsSettled(true)` later. Harmless
      // today because React bails out of the resulting no-op re-render, but a timer left armed
      // after its reason has passed is real state a later change could trip over — so this
      // asserts the timer itself, via the fake-timer queue, rather than an absence of behavior
      // that would stay true for the wrong reason if some other effect changed shape.
      vi.useFakeTimers();
      try {
        readCached.mockReturnValue(null);
        prefsGet.mockResolvedValue({ slug: "acme" });
        render(<Shell />);

        // The GET is already resolved; flushing by 0ms still drains the microtask queue that
        // its `.then` runs on, without needing to reach anywhere near the 5s mark.
        await act(async () => {
          await vi.advanceTimersByTimeAsync(0);
        });

        expect(vi.getTimerCount()).toBe(0);
      } finally {
        vi.useRealTimers();
      }
    },
  );

  it(
    "[round 5, matrix rows t01/u01] a mount torn down before its prefs GET settles never " +
      "mirrors that answer into the cache",
    async () => {
      // The `.then`'s `!alive` return and the cleanup's `alive = false` are two halves of one
      // guard, and the matrix found both free: deleting either left 33 green. What they prevent
      // is a DEAD mount writing localStorage. The mirror is gated on `wroteLocally`, which is a
      // per-mount ref — so a mount whose GET is still in flight when the user navigates away
      // knows nothing about a write made by the mount that replaced it, and its late answer
      // would roll the cache back to the pre-write row. That rollback is invisible until the
      // cache is next CONSULTED, which only happens when a later read fails: the one moment
      // nothing can correct it. Nothing that outlives the mount may touch storage.
      readCached.mockReturnValue(null);
      let settlePrefs: (p: { slug?: string }) => void = () => {};
      prefsGet.mockReturnValue(new Promise((r) => (settlePrefs = r)));

      const { unmount } = render(<Shell />);
      await waitFor(() => expect(screen.getByTestId("picker")).toBeInTheDocument());
      unmount();

      await act(async () => {
        settlePrefs({ slug: "mine" });
        await new Promise((r) => setTimeout(r, 0));
      });

      expect(writeCached.mock.calls.flat()).toEqual([]);
    },
  );

  it(
    "[round 5, matrix row u02] unmounting with the prefs GET still in flight leaves no armed " +
      "bail timer",
    async () => {
      // The unmount half of `clearTimeout(bail)`. Round 3 pinned the settle-path clear and round
      // 4 the reject-path clear; this is the third arm, and the matrix found it free. Same
      // standard as those two: assert the timer QUEUE, not an absence of behaviour that would
      // stay true for the wrong reason. `alive = false` already makes the late callback a no-op,
      // so the only thing left to observe is the timer itself.
      vi.useFakeTimers();
      try {
        readCached.mockReturnValue(null);
        prefsGet.mockReturnValue(new Promise(() => {})); // never settles
        const { unmount } = render(<Shell />);
        expect(vi.getTimerCount()).toBe(1);

        unmount();

        expect(vi.getTimerCount()).toBe(0);
      } finally {
        vi.useRealTimers();
      }
    },
  );

  it(
    "[round 3, finding 3 regression] a successful prefs GET warms the cache even though " +
      "nothing else writes",
    async () => {
      // No URL slug, and the cache already agrees with the server, so the persistence effect has
      // nothing to do: `pendingWrite` starts null here (there was no explicit act — no deep link,
      // no pick), its guard never passes, and neither a PUT nor the persistence effect's OWN
      // cache write ever happens for this render. Before finding 3, that left the cache cold
      // forever for exactly the users the cache exists to serve: someone who reads their
      // preference successfully and never switches workspace on this browser. The GET's own
      // `.then` is now the one writing it, independent of whether the persistence effect ever
      // fires.
      readCached.mockReturnValue("acme");
      let settlePrefs: (p: { slug?: string }) => void = () => {};
      prefsGet.mockReturnValue(new Promise((r) => (settlePrefs = r)));

      render(<Shell />);
      await waitFor(() =>
        expect(screen.getByRole("button", { name: "Acme" })).toBeInTheDocument(),
      );
      expect(writeCached).not.toHaveBeenCalled();

      await act(async () => {
        settlePrefs({ slug: "acme" });
        await new Promise((r) => setTimeout(r, 0));
      });

      expect(writeCached).toHaveBeenCalledWith("acme");
      // And confirm it really is the GET's mirror doing the writing, not the persistence effect
      // quietly doing its usual job too.
      expect(prefsPut).not.toHaveBeenCalled();
    },
  );

  it("deep link wins over the stored preference — lands on acme with exactly one PUT", async () => {
    readCached.mockReturnValue("mine");
    render(<Shell workspaceSlug="acme" />);
    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
    expect(replace).not.toHaveBeenCalled();
    await waitFor(() => expect(prefsPut).toHaveBeenCalledTimes(1));
    expect(prefsPut).toHaveBeenCalledWith({ slug: "acme" });
    expect(writeCached).toHaveBeenCalledWith("acme");
  });

  it(
    "[round 2 + round 4, finding 1 regression] deep link acme, cold cache — one PUT, and a late " +
      "GET answering a DIFFERENT workspace neither re-fires the persistence effect nor rolls " +
      "the cache back to its pre-PUT row",
    async () => {
      // Round 1 left a milder version of finding 2's bug: a cold cache meant `stored` started
      // null, and the late `setStored` from the prefs answer re-triggered the persistence effect
      // a second time, emitting a duplicate identical PUT. `pendingWrite` fixes this the same way
      // it fixes the destructive case: it is cleared the first time it is consumed, so a later
      // `stored` update cannot re-fire the effect no matter what it names.
      readCached.mockReturnValue(null);
      let settlePrefs: (p: { slug?: string }) => void = () => {};
      prefsGet.mockReturnValue(new Promise((r) => (settlePrefs = r)));

      render(<Shell workspaceSlug="acme" />);
      await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
      expect(replace).not.toHaveBeenCalled();
      await waitFor(() => expect(prefsPut).toHaveBeenCalledTimes(1));
      expect(prefsPut).toHaveBeenCalledWith({ slug: "acme" });
      expect(writeCached).toHaveBeenCalledTimes(1);

      // The late prefs answer must not re-trigger the PERSISTENCE EFFECT, even naming a
      // DIFFERENT workspace than the one already landed on. Wrapped in `act` so the resulting
      // `setStored` and any effect it schedules are fully flushed before we check — a bare tick
      // left the re-fire pending past the assertion and produced a false pass against the buggy
      // code.
      await act(async () => {
        settlePrefs({ slug: "mine" });
        await new Promise((r) => setTimeout(r, 0));
      });
      // [round 4, finding 1] round 3 mirrored the GET's answer to the cache UNCONDITIONALLY, so
      // this test used to assert a second write naming "mine" — it was pinning a bug. That row
      // predates the PUT this mount just issued: the GET was in flight before the deep link was
      // even persisted, so writing it rolls the cache back to a workspace the user is no longer
      // on. And nothing corrects it, because the cache is consulted ONLY when a later read fails
      // — precisely when no successful read exists to fix it. So the gate: a read never
      // overwrites a write. One cache write total, naming what was actually chosen.
      //
      // `prefsPut` staying at one call is still the round-2 assertion this test was written for
      // (the persistence effect must not re-fire on the late `setStored`); `writeCached` at one
      // call is now BOTH that and the finding-1 rollback guard.
      expect(prefsPut).toHaveBeenCalledTimes(1);
      // Asserted as the whole SEQUENCE, not a count plus a last-call: what went wrong here was a
      // second write of a specific stale value, so a red should print the sequence that was
      // actually observed. Against the round-3 blob this reads `["acme", "mine"]`.
      expect(writeCached.mock.calls.flat()).toEqual(["acme"]);
    },
  );

  it(
    "[round 4, finding 1 regression] a pick made while the prefs GET is still in flight is not " +
      "rolled back when that GET answers a different workspace",
    async () => {
      // The second interleaving finding 1 measured. The user is on "mine", picks "beta", and the
      // GET — issued at mount, before that pick existed — answers "acme" afterwards. Round 3's
      // unconditional mirror wrote "acme" into the cache on top of the just-PUT "beta", so the
      // next session whose GET failed would fall back to the cache and `router.replace` the user
      // onto a workspace they had explicitly navigated away from.
      readCached.mockReturnValue("mine");
      list.mockResolvedValue([
        ...WORKSPACES,
        { slug: "beta", name: "Beta", kind: "organization" as const },
      ]);
      let settlePrefs: (p: { slug?: string }) => void = () => {};
      prefsGet.mockReturnValue(new Promise((r) => (settlePrefs = r)));

      render(<Shell workspaceSlug="mine" />);
      await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
      // Arriving on the workspace the cache already names settles nothing on its own.
      expect(writeCached).not.toHaveBeenCalled();

      fireEvent.click(screen.getByRole("button", { name: "Beta" }));
      await waitFor(() => expect(prefsPut).toHaveBeenCalledWith({ slug: "beta" }));
      expect(writeCached).toHaveBeenCalledTimes(1);
      expect(writeCached).toHaveBeenCalledWith("beta");

      // Now the in-flight GET lands with the row as it stood BEFORE that PUT.
      await act(async () => {
        settlePrefs({ slug: "acme" });
        await new Promise((r) => setTimeout(r, 0));
      });

      // Same whole-sequence assertion as the test above. Against the round-3 blob this reads
      // `["beta", "acme"]` — the pick, then the pre-pick row rolled back over it.
      expect(writeCached.mock.calls.flat()).toEqual(["beta"]);
      // And the pick is not undone anywhere else either: the URL still names it, and no second
      // PUT was provoked.
      expect(screen.getByTestId("picker")).toHaveAttribute("data-selected", "beta");
      expect(prefsPut).toHaveBeenCalledTimes(1);
    },
  );

  it(
    "[round 5, finding 1 regression] after a local write, a history navigation to a bare URL " +
      "re-seeds from the LOCALLY-written slug, not the late GET's older row",
    async () => {
      // The `setStored` half of the `wroteLocally` gate — the half round 4 shipped unasserted.
      // Gating only `writeCachedWorkspace` and leaving `setStored` ungated left all 32 of round
      // 4's tests green while changing where the user LANDS, which is the harm finding 1 exists
      // to prevent, arriving through the other door.
      //
      // Cold cache, deep link `/acme`: the shell PUTs `{acme}`, caches it, and records the
      // write. The GET — issued at mount, before that write existed — answers the pre-PUT row
      // `mine`. Then Back lands on a URL carrying no workspace segment, so the shell has to seed
      // one, and `known(stored)` is the seed. `stored` must still be the slug the write put
      // there. (An unknown slug no longer reaches that branch at all — `known()` rejects it and
      // the resolution stops, which is the refusal the four tests below the redirect cases pin.
      // This case is about the ABSENT slug, the one the seed still serves.)
      readCached.mockReturnValue(null);
      let settlePrefs: (p: { slug?: string }) => void = () => {};
      prefsGet.mockReturnValue(new Promise((r) => (settlePrefs = r)));

      render(<Shell workspaceSlug="acme" />);
      await waitFor(() => expect(prefsPut).toHaveBeenCalledWith({ slug: "acme" }));
      // The URL already named the resolution, so nothing has been replaced yet — the assertion
      // below is about the ONE replace the history navigation provokes.
      expect(replace).not.toHaveBeenCalled();

      await act(async () => {
        settlePrefs({ slug: "mine" });
        await new Promise((r) => setTimeout(r, 0));
      });

      await act(async () => {
        liveSetSlug(undefined);
        await new Promise((r) => setTimeout(r, 0));
      });

      await waitFor(() => expect(replace).toHaveBeenCalledTimes(1));
      expect(replace).toHaveBeenCalledWith("/acme", { scroll: false });
      await waitFor(() =>
        expect(screen.getByTestId("picker")).toHaveAttribute("data-selected", "acme"),
      );
    },
  );

  it(
    "[round 4, finding 1] the mirror still warms a COLD cache when no local write has happened",
    async () => {
      // The finding-3 behaviour the gate must not cost: nothing in localStorage, no URL slug, so
      // `pendingWrite` is null and the persistence effect can never fire — the GET's own mirror is
      // the only writer there is. `wroteLocally` is false throughout, so it writes.
      readCached.mockReturnValue(null);
      prefsGet.mockResolvedValue({ slug: "acme" });

      render(<Shell />);
      await waitFor(() => expect(replace).toHaveBeenCalledWith("/acme", { scroll: false }));

      expect(writeCached).toHaveBeenCalledTimes(1);
      expect(writeCached).toHaveBeenCalledWith("acme");
      expect(prefsPut).not.toHaveBeenCalled();
    },
  );

  it(
    "[round 4, finding 1] the bail path still warms the cache when the true row arrives after " +
      "the timeout",
    async () => {
      // The other behaviour the gate must not cost. The GET outruns the 5s bail, so the shell
      // seeds and lands on the personal workspace — a guess, which is never written (0 PUTs, and
      // `wroteLocally` stays false). When the real row finally arrives it cannot displace the
      // guess in the URL (deliberate: the URL is a live instruction), but it MUST still warm the
      // cache, or the very users the bail exists for keep a cold one.
      vi.useFakeTimers();
      try {
        readCached.mockReturnValue(null);
        let settlePrefs: (p: { slug?: string }) => void = () => {};
        prefsGet.mockReturnValue(new Promise((r) => (settlePrefs = r)));
        render(<Shell />);

        await act(async () => {
          await vi.advanceTimersByTimeAsync(5000);
        });
        expect(replace).toHaveBeenCalledWith("/mine", { scroll: false });
        expect(writeCached).not.toHaveBeenCalled();

        await act(async () => {
          settlePrefs({ slug: "acme" });
          await vi.advanceTimersByTimeAsync(0);
        });

        expect(writeCached).toHaveBeenCalledTimes(1);
        expect(writeCached).toHaveBeenCalledWith("acme");
        // The late answer warms the cache and nothing else: the guess in the URL stands, and the
        // seed is still never persisted.
        expect(replace).toHaveBeenCalledTimes(1);
        expect(prefsPut).not.toHaveBeenCalled();
      } finally {
        vi.useRealTimers();
      }
    },
  );

  it(
    "[max review, finding 2 regression] the slug the shell SEEDED into the URL is still a guess " +
      "to the mount the redirect lands on — zero PUTs",
    async () => {
      // Every other "a guess is never persisted" case above is measured on ONE mount, where
      // `pendingWrite` remembers that nobody asked for this slug. The redirect crosses a route
      // boundary — a site's `/home` and its `/<workspace>` are two Next routes — so the mount that
      // reads the seeded URL is a different one, with that memory gone, and it used to read its own
      // predecessor's guess back as a deep link and PUT it over the row the user actually chose.
      // That is the whole failure this file exists to prevent, arrived at one hop later.
      vi.useFakeTimers();
      try {
        readCached.mockReturnValue(null);
        // Mount A — bare `/home`, cold cache, a prefs GET that never answers. The 5s bail is what
        // makes the seed a guess made against NO information at all.
        prefsGet.mockReturnValueOnce(new Promise(() => {}));
        const first = render(<Shell />);
        await act(async () => {
          await vi.advanceTimersByTimeAsync(5000);
        });
        expect(replace).toHaveBeenCalledWith("/mine", { scroll: false });
        expect(prefsPut).not.toHaveBeenCalled();

        // The route change that redirect really is. Unmount, then mount afresh at the seeded URL:
        // a prop update would keep the state that knows the slug was guessed, so only a remount
        // can show the defect.
        first.unmount();
        // This mount's GET succeeds, and answers the workspace the user chose on another site.
        prefsGet.mockReturnValueOnce(Promise.resolve({ slug: "acme" }));
        render(<Shell workspaceSlug="mine" />);
        await act(async () => {
          await vi.advanceTimersByTimeAsync(0);
        });

        // The guess is displayed, never recorded: the server row is not overwritten with it...
        expect(prefsPut).not.toHaveBeenCalled();
        // ...and the row that was really there is what warms the cache, so the next visit — the
        // one that reads the cache because its own request failed — lands on the user's choice.
        expect(writeCached.mock.calls.flat()).toEqual(["acme"]);
        // The URL still names the guess, and stays that way: it is what the user is looking at,
        // and re-resolving underneath them would be a page that reshuffles itself.
        expect(screen.getByTestId("picker")).toHaveAttribute("data-selected", "mine");
        expect(replace).toHaveBeenCalledTimes(1);
      } finally {
        vi.useRealTimers();
      }
    },
  );

  it(
    "[max review, finding 2] the seed marker excuses ONE hop — a later arrival on the same slug " +
      "is the user's and is persisted",
    async () => {
      // The other half of the marker's contract. It is a fact about one redirect, not a standing
      // claim about a slug: if it survived, then for the rest of the page's life every arrival on
      // the workspace the shell once guessed would be silently un-persisted, and a user who
      // reached `/mine` from a link would keep failing to have that choice remembered.
      vi.useFakeTimers();
      try {
        readCached.mockReturnValue(null);
        prefsGet.mockReturnValueOnce(new Promise(() => {}));
        const first = render(<Shell />); // `/home` → bail → seeds `/mine`
        await act(async () => {
          await vi.advanceTimersByTimeAsync(5000);
        });
        first.unmount();

        prefsGet.mockReturnValueOnce(Promise.resolve({ slug: "acme" }));
        const second = render(<Shell workspaceSlug="mine" />); // the hop the marker excuses
        await act(async () => {
          await vi.advanceTimersByTimeAsync(0);
        });
        expect(prefsPut).not.toHaveBeenCalled();
        second.unmount();

        // A third mount on the same URL, with nothing left to excuse it: the user followed a link
        // (or reloaded) onto `/mine`, which is an explicit act like any other deep link. The cache
        // now holds what the second mount's GET mirrored, so the PUT has something to disagree
        // with — the same shape as the deep-link case above.
        readCached.mockReturnValue("acme");
        render(<Shell workspaceSlug="mine" />);
        await act(async () => {
          await vi.advanceTimersByTimeAsync(0);
        });
        expect(prefsPut).toHaveBeenCalledTimes(1);
        expect(prefsPut).toHaveBeenCalledWith({ slug: "mine" });
      } finally {
        vi.useRealTimers();
      }
    },
  );

  it(
    "[max review 2, finding 4 regression] a SUPERSEDED seeding replace leaves nothing behind — a " +
      "later deliberate arrival on that slug is still the user's, and is persisted",
    async () => {
      // The marker is written BEFORE the replace, because the replace may unmount the hook. So it
      // is a promise about a mount that is not guaranteed to happen: `router.replace` can be
      // superseded — the visitor clicks a link, or hits Back, while the transition is in flight —
      // and then there is no arrival to consume it. Clearing it only on a MATCHING mount left it
      // standing for the life of the tab, and every later arrival on that one slug, by link or by
      // hand, was silently read as this hook's own old guess and never persisted.
      vi.useFakeTimers();
      try {
        readCached.mockReturnValue(null);
        // Mount A — bare `/home`, cold cache, a GET that never answers, so the 5s bail seeds
        // `/mine`. `routerFeedsBack = false` IS the supersession: the replace is issued and the
        // arrival it was written for never comes.
        routerFeedsBack = false;
        prefsGet.mockReturnValueOnce(new Promise(() => {}));
        const first = render(<Shell />);
        await act(async () => {
          await vi.advanceTimersByTimeAsync(5000);
        });
        expect(replace).toHaveBeenCalledWith("/mine", { scroll: false });
        first.unmount();

        // Where the visitor actually went. Nothing here matches the marker — which is exactly why
        // this mount has to consume it: a mount somewhere else is proof the hop is over.
        routerFeedsBack = true;
        readCached.mockReturnValue("acme");
        prefsGet.mockReturnValueOnce(Promise.resolve({ slug: "acme" }));
        const second = render(<Shell workspaceSlug="acme" />);
        await act(async () => {
          await vi.advanceTimersByTimeAsync(0);
        });
        // Arriving on the workspace already stored settles nothing on its own, so the PUT counted
        // below can only have come from the third mount.
        expect(prefsPut).not.toHaveBeenCalled();
        second.unmount();

        // And now the arrival the stale marker used to swallow: a deliberate navigation onto the
        // slug the shell once guessed, well inside the handoff window, with the stored row
        // disagreeing. It is a deep link like any other.
        prefsGet.mockReturnValueOnce(Promise.resolve({ slug: "acme" }));
        render(<Shell workspaceSlug="mine" />);
        await act(async () => {
          await vi.advanceTimersByTimeAsync(0);
        });
        expect(prefsPut).toHaveBeenCalledTimes(1);
        expect(prefsPut).toHaveBeenCalledWith({ slug: "mine" });
      } finally {
        vi.useRealTimers();
      }
    },
  );

  it(
    "[max review 2, finding 4 regression] an unconsumed seed marker EXPIRES, so a return " +
      "minutes later is an arrival and not a stale guess",
    async () => {
      // The other end of the same defect, and the reason consuming on every mount is not enough
      // on its own: the superseded case may mount this hook NOWHERE at all — the visitor leaves
      // for a route without the shell, or another site — and comes back to that same slug
      // themselves later. There is no mount in between to spend the marker, so only the clock can.
      vi.useFakeTimers();
      try {
        readCached.mockReturnValue(null);
        routerFeedsBack = false;
        prefsGet.mockReturnValueOnce(new Promise(() => {}));
        const first = render(<Shell />);
        await act(async () => {
          await vi.advanceTimersByTimeAsync(5000);
        });
        expect(replace).toHaveBeenCalledWith("/mine", { scroll: false });
        first.unmount();

        // Five minutes of reading something else. A client route transition is sub-second, so
        // anything on this scale is a person, not a handoff.
        await act(async () => {
          await vi.advanceTimersByTimeAsync(300_000);
        });

        routerFeedsBack = true;
        readCached.mockReturnValue("acme");
        prefsGet.mockReturnValueOnce(Promise.resolve({ slug: "acme" }));
        render(<Shell workspaceSlug="mine" />);
        await act(async () => {
          await vi.advanceTimersByTimeAsync(0);
        });
        expect(prefsPut).toHaveBeenCalledTimes(1);
        expect(prefsPut).toHaveBeenCalledWith({ slug: "mine" });
      } finally {
        vi.useRealTimers();
      }
    },
  );

  it(
    "[max review 2, finding 7 regression] the seeding redirect carries the query and the fragment",
    async () => {
      // `/home` is the one address the whole family hands out — the header's Home link, the SSO
      // return target, any campaign-tagged share of it — and the redirect that repairs it used to
      // rebuild the destination from the slug alone, dropping everything after the path. The
      // legacy `/home` → `/<workspace>` redirects in the sites' next configs preserve it, so the
      // loss showed up as the OLD URL shape working where the new one did not.
      window.history.replaceState({}, "", "/home?invite=abc#team");
      readCached.mockReturnValue(null);
      prefsGet.mockResolvedValue({ slug: "acme" });

      render(<Shell />);
      await waitFor(() =>
        expect(replace).toHaveBeenCalledWith("/acme?invite=abc#team", { scroll: false }),
      );
      // And the segment the shell then reads is still just the slug: the extras ride along, they
      // do not become part of the workspace's name.
      await waitFor(() =>
        expect(screen.getByTestId("feature")).toHaveAttribute("data-workspace", "acme"),
      );
    },
  );

  it(
    "[round 4, finding 2 regression] the bail timer is cleared when the GET REJECTS too — zero " +
      "armed timers",
    async () => {
      // Round 3 cleared the bail in both `.then` and `.catch`, but only the `.then` half was
      // asserted: deleting `clearTimeout(bail)` from the `.catch` left all 27 tests green. A
      // rejection is the path where a leftover timer is most plausible to matter, since the
      // rejection handler is also the one that opens the seed gate.
      vi.useFakeTimers();
      try {
        readCached.mockReturnValue(null);
        prefsGet.mockRejectedValue(new Error("offline"));
        render(<Shell />);

        await act(async () => {
          await vi.advanceTimersByTimeAsync(0);
        });

        expect(vi.getTimerCount()).toBe(0);
      } finally {
        vi.useRealTimers();
      }
    },
  );

  it(
    "[round 4, finding 3] a lingering pendingWrite still writes on a RETURN navigation, once a " +
      "late GET has moved `stored` out from under it",
    async () => {
      // This pins the claim the `pendingWrite` comment now makes. Deep link `/acme` with the
      // cache already agreeing: the persistence effect skips on `resolved === stored` and — since
      // round 3 — clears `pendingWrite` only AFTER that skip, so it survives. Navigate away to
      // `beta` (nothing fires: `pendingWrite` names "acme"). A late GET answers "mine", moving
      // `stored`. Navigate back to `acme`: the record of the original arrival is still there and
      // the PUT it earned finally fires — later than the arrival, which is the point.
      readCached.mockReturnValue("acme");
      list.mockResolvedValue([
        ...WORKSPACES,
        { slug: "beta", name: "Beta", kind: "organization" as const },
      ]);
      let settlePrefs: (p: { slug?: string }) => void = () => {};
      prefsGet.mockReturnValue(new Promise((r) => (settlePrefs = r)));

      render(<Shell workspaceSlug="acme" />);
      await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
      expect(prefsPut).not.toHaveBeenCalled();

      // A history navigation — the URL moves with no push/replace and no pick.
      await act(async () => {
        liveSetSlug("beta");
        await new Promise((r) => setTimeout(r, 0));
      });
      expect(prefsPut).not.toHaveBeenCalled();

      await act(async () => {
        settlePrefs({ slug: "mine" });
        await new Promise((r) => setTimeout(r, 0));
      });
      expect(prefsPut).not.toHaveBeenCalled();

      await act(async () => {
        liveSetSlug("acme");
        await new Promise((r) => setTimeout(r, 0));
      });

      await waitFor(() => expect(prefsPut).toHaveBeenCalledTimes(1));
      expect(prefsPut).toHaveBeenCalledWith({ slug: "acme" });
    },
  );

  it(
    "[round 3, finding 1 regression] warm cache acme, deep link /acme, server row mine, " +
      'the list settles before the GET — exactly one PUT, {slug: "acme"}',
    async () => {
      // The exact shape finding 1 named: the cache already agrees with the deep link, but the
      // server row still names a DIFFERENT workspace. Before the fix, `pendingWrite` cleared
      // BEFORE the `resolved === stored` skip — so on this first (list-only) pass, `resolved
      // ("acme") === stored ("acme")` short-circuited, but the clear had already run, throwing
      // `pendingWrite` away. When the server's late "mine" then changed `stored`, nothing was
      // left for the guard to match, and the PUT the user's own deep link asked for never fired.
      readCached.mockReturnValue("acme");
      let settleList: (w: typeof WORKSPACES) => void = () => {};
      list.mockReturnValue(new Promise((r) => (settleList = r)));
      let settlePrefs: (p: { slug?: string }) => void = () => {};
      prefsGet.mockReturnValue(new Promise((r) => (settlePrefs = r)));

      render(<Shell workspaceSlug="acme" />);

      // The list lands first — `resolved` becomes "acme" while `stored` still reads the cache's
      // own "acme", so the persistence effect's `resolved === stored` skip fires and nothing
      // writes yet.
      await act(async () => {
        settleList(WORKSPACES);
        await new Promise((r) => setTimeout(r, 0));
      });
      expect(prefsPut).not.toHaveBeenCalled();

      // The server's answer arrives after, naming a DIFFERENT workspace than the deep link.
      await act(async () => {
        settlePrefs({ slug: "mine" });
        await new Promise((r) => setTimeout(r, 0));
      });

      await waitFor(() => expect(prefsPut).toHaveBeenCalledTimes(1));
      expect(prefsPut).toHaveBeenCalledWith({ slug: "acme" });
    },
  );

  it(
    "[round 3, finding 1 regression] warm cache acme, deep link /acme, server row mine, " +
      'the GET settles before the list — same outcome: exactly one PUT, {slug: "acme"}',
    async () => {
      // Mirror-image ordering of the case above, so together they pin the actual invariant:
      // finding 1 was that the SAME user action produced opposite outcomes depending on which
      // request won the race. Both orderings must land on exactly one PUT naming "acme".
      readCached.mockReturnValue("acme");
      let settleList: (w: typeof WORKSPACES) => void = () => {};
      list.mockReturnValue(new Promise((r) => (settleList = r)));
      let settlePrefs: (p: { slug?: string }) => void = () => {};
      prefsGet.mockReturnValue(new Promise((r) => (settlePrefs = r)));

      render(<Shell workspaceSlug="acme" />);

      // The server answers first, while `resolved` is still undefined (the list hasn't loaded,
      // so the persistence effect's own `!resolved` guard keeps it from firing at all yet).
      await act(async () => {
        settlePrefs({ slug: "mine" });
        await new Promise((r) => setTimeout(r, 0));
      });
      expect(prefsPut).not.toHaveBeenCalled();

      // The list lands after — this is the pass where `resolved` first becomes "acme".
      await act(async () => {
        settleList(WORKSPACES);
        await new Promise((r) => setTimeout(r, 0));
      });

      await waitFor(() => expect(prefsPut).toHaveBeenCalledTimes(1));
      expect(prefsPut).toHaveBeenCalledWith({ slug: "acme" });
    },
  );

  it("[round 2] deep link to the workspace already stored — zero PUTs", async () => {
    readCached.mockReturnValue("acme");
    render(<Shell workspaceSlug="acme" />);
    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
    // Give the persistence effect a further tick to fire before asserting it stayed silent.
    await new Promise((r) => setTimeout(r, 0));
    expect(prefsPut).not.toHaveBeenCalled();
    expect(writeCached).not.toHaveBeenCalled();
  });

  it("[finding 2 regression] user picks acme from mine — exactly one cache write and one PUT, both acme, no intermediate mine", async () => {
    // The cache already agrees with the URL, so landing on "mine" settles nothing on its own —
    // the only write this test should see is the one caused by the pick below.
    readCached.mockReturnValue("mine");
    render(<Shell workspaceSlug="mine" />);
    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
    expect(prefsPut).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Acme" }));
    await waitFor(() => expect(prefsPut).toHaveBeenCalledTimes(1));
    expect(prefsPut).toHaveBeenCalledWith({ slug: "acme" });
    expect(writeCached).toHaveBeenCalledTimes(1);
    expect(writeCached).toHaveBeenCalledWith("acme");
  });

  it(
    "[round 2] two picks in quick succession — only the second (beta) is written, with no " +
      "intermediate acme",
    async () => {
      // Both clicks fire synchronously, before either router.push's deferred URL update lands.
      // `pendingWrite` is overwritten by the second pick before the first's URL update ever
      // renders, so the persistence effect's `pendingWrite !== resolved` guard rejects that
      // transient "acme" render and only the final "beta" is ever written.
      readCached.mockReturnValue("mine");
      list.mockResolvedValue([...WORKSPACES, { slug: "beta", name: "Beta", kind: "organization" as const }]);
      render(<Shell workspaceSlug="mine" />);
      await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());

      fireEvent.click(screen.getByRole("button", { name: "Acme" }));
      fireEvent.click(screen.getByRole("button", { name: "Beta" }));

      await waitFor(() => expect(prefsPut).toHaveBeenCalledTimes(1));
      expect(prefsPut).toHaveBeenCalledWith({ slug: "beta" });
      expect(writeCached).toHaveBeenCalledTimes(1);
      expect(writeCached).toHaveBeenCalledWith("beta");
    },
  );

  it("renders the caller's own profile for an unreachable URL slug, not a redirect to the stored preference", async () => {
    // The behaviour this replaced: `/zzz` resolved to the stored preference and REPLACED the URL
    // with it, so a renamed or deleted workspace's links silently became someone's own workspace
    // with the address bar rewritten to match. A stored preference is the strongest possible pull
    // toward that old answer, which is why this case keeps one — the shell must still land on
    // `zzz`'s own profile rather than pulling toward "acme".
    readCached.mockReturnValue("acme");
    renderReachable({ workspaceSlug: "zzz" });
    await waitFor(() => expect(screen.getByTestId("profile-fallback")).toBeInTheDocument());
    expect(screen.getByTestId("profile-fallback")).toHaveAttribute("data-slug", "zzz");
    expect(replace).not.toHaveBeenCalled();
    expect(push).not.toHaveBeenCalled();
    expect(prefsPut).not.toHaveBeenCalled();
    expect(writeCached).not.toHaveBeenCalled();
  });

  it("hands the fallback the site it is MOUNTED on, not a hardcoded one", async () => {
    // The one case that mounts a site other than the hub, and the only thing in this file that can
    // fail if the shell stops reading `useSiteIdOrNull()` and hardcodes an id instead. "hub" is the
    // literal such a bug would use — the hub's own WorkspaceGate hardcodes exactly that — so a case
    // asserting "hub" would pass against the bug it is meant to catch. This one asserts "projects".
    renderReachable({ workspaceSlug: "zzz" }, "projects");
    await waitFor(() => expect(screen.getByTestId("profile-fallback")).toBeInTheDocument());
    expect(screen.getByTestId("profile-fallback")).toHaveAttribute("data-site-id", "projects");
  });

  it("[round 2] back button from acme to mine — zero PUTs", async () => {
    // The URL changes (as the browser's back button does) with no pick and no push/replace call
    // — `pendingWrite` was already cleared by acme's own landing, so it cannot match "mine" and
    // the persistence effect stays inert. The spec's fallback is for arrival, not for reversal:
    // going back must not re-persist the workspace you're leaving.
    readCached.mockReturnValue("acme");
    render(<Shell workspaceSlug="acme" />);
    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
    expect(prefsPut).not.toHaveBeenCalled();

    act(() => {
      liveSetSlug("mine");
    });
    await waitFor(() =>
      expect(screen.getByTestId("picker")).toHaveAttribute("data-selected", "mine"),
    );
    // Give the persistence effect a further tick to fire before asserting it stayed silent.
    await new Promise((r) => setTimeout(r, 0));
    expect(prefsPut).not.toHaveBeenCalled();
    expect(writeCached).not.toHaveBeenCalled();
  });

  it("with no slug, resolves to the stored preference over the personal workspace", async () => {
    readCached.mockReturnValue("acme");
    render(<Shell />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith("/acme", { scroll: false }));
  });

  it("drops a stored slug that is no longer in the list", async () => {
    readCached.mockReturnValue("gone");
    render(<Shell />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith("/mine", { scroll: false }));
  });

  it("renders the caller's own profile for an unknown slug with nothing stored — the personal workspace is not a fallback", async () => {
    // The other half of the old rewrite: with no preference to fall back to it used `workspaces[0]`,
    // the personal workspace. Pinned separately because the two arrived by different lines in the
    // resolution and a fix could plausibly have caught only one.
    renderReachable({ workspaceSlug: "nope" });
    await waitFor(() => expect(screen.getByTestId("profile-fallback")).toBeInTheDocument());
    expect(screen.getByTestId("profile-fallback")).toHaveAttribute("data-slug", "nope");
    expect(replace).not.toHaveBeenCalled();
    expect(screen.queryByTestId("feature")).toBeNull();
  });

  it("renders the caller's own profile for a slug they are not in, even with an empty list", async () => {
    // A user with no workspaces at all. `/acme` still lands on the profile branch, not the
    // "No workspaces yet" hint: the hint answers "where should I go", which is `/home`'s question,
    // and this URL asked a different one. Worth its own row because the empty list is the one case
    // where there is no workspace to redirect TO, so a hold-shaped bug here would look identical to
    // the profile branch simply never firing.
    list.mockResolvedValue([]);
    renderReachable({ workspaceSlug: "acme" });
    await waitFor(() => expect(screen.getByTestId("profile-fallback")).toBeInTheDocument());
    expect(screen.getByTestId("profile-fallback")).toHaveAttribute("data-slug", "acme");
    expect(replace).not.toHaveBeenCalled();
  });

  it("does NOT show the profile while the list is still loading", async () => {
    // The rung directly below the profile branch, and the one that makes it dangerous to express
    // as `resolved === undefined`: resolution is `undefined` both while loading and on a slug that
    // will land on the profile. Held here by the list never settling — if the shell read a null
    // list as "settled without acme" it would show a stranger's profile for a workspace the caller
    // genuinely has.
    list.mockReturnValue(new Promise(() => {}));
    renderReachable({ workspaceSlug: "acme" });
    await new Promise((r) => setTimeout(r, 0));
    expect(screen.queryByTestId("profile-fallback")).toBeNull();
    expect(screen.queryByTestId("feature")).toBeNull();
  });

  it("does NOT show the profile for a slug missing from a STALE SEED while the refetch is still out", async () => {
    // The fourth rung. `useResourceList` seeds the first render from its module cache, so the list
    // can be non-null AND predate the workspace the URL names — which is exactly the render a
    // freshly-created workspace is absent from. Read as "settled without newco", that would show
    // the owner a stranger's profile in place of the workspace they just made.
    //
    // Held here by seeding rows that lack `newco` and never settling the refetch, so the only
    // thing that could keep the shell off the profile branch is the in-flight flag: the list is
    // non-null, it does not carry the slug, and no error has been recorded.
    seedRows = WORKSPACES;
    list.mockReturnValue(new Promise(() => {}));
    renderReachable({ workspaceSlug: "newco" });
    await new Promise((r) => setTimeout(r, 0));
    expect(screen.queryByTestId("profile-fallback")).toBeNull();
  });

  it("...and DOES show the profile once that refetch lands without it", async () => {
    // The other half, so the rung above is a delay and not an exemption: the same seeded mount,
    // with the read allowed to settle, still lands on the profile. Without this a stuck
    // `isFetching` would disable the profile branch outright and every test in this group would
    // keep passing.
    seedRows = WORKSPACES;
    list.mockResolvedValue(WORKSPACES);
    renderReachable({ workspaceSlug: "newco" });
    await waitFor(() => expect(screen.getByTestId("profile-fallback")).toBeInTheDocument());
    expect(screen.getByTestId("profile-fallback")).toHaveAttribute("data-slug", "newco");
  });

  it("does NOT show the profile when the list FAILED — a retryable error is not a verdict", async () => {
    // `useResourceList` leaves `items` null on a cold failure, so "the list says you are not a
    // member" and "there is no list" are one value apart. Turning a transient 5xx into someone's
    // profile page would strand a member on the wrong page for a workspace they can in fact reach;
    // the hub's WorkspaceGate draws the same line, offering a Retry rather than refusing.
    list.mockRejectedValue(new Error("boom"));
    renderReachable({ workspaceSlug: "acme" });
    await waitFor(() =>
      expect(screen.getByText(/Couldn't load your workspaces/)).toBeInTheDocument(),
    );
    expect(screen.queryByTestId("profile-fallback")).toBeNull();
    expect(replace).not.toHaveBeenCalled();
  });

  it("does NOT show the profile at the bare /home, which names no slug to show one for", async () => {
    // The redirect signal still works. This is the one URL the resolution is still allowed to
    // repair, and the profile branch is scoped by `workspaceSlug !== undefined` so it cannot reach
    // here. No `<SiteIdProvider>` either — this is the one case in the group that mirrors `/home`'s
    // real mount, which sits outside the `[workspace]` layout that provides it.
    readCached.mockReturnValue("acme");
    render(<Shell />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith("/acme", { scroll: false }));
    expect(screen.queryByTestId("profile-fallback")).toBeNull();
  });

  it("mounts children once the URL matches the resolved workspace", async () => {
    render(<Shell workspaceSlug="mine" />);
    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
  });

  it(
    "[round 5, matrix row d06] children stay unmounted while the URL still disagrees with the " +
      "resolution, not merely while it is undecided",
    async () => {
      // The children guard has three conjuncts and only the `resolved !== undefined` one was
      // pinned: dropping `resolved === workspaceSlug` left 33 green, because every other test
      // lets the harness's replace feed the URL back within a microtask, so the disagreement
      // never lasts long enough to observe. The real router's does last — a navigation is not
      // instantaneous — and the feature underneath reads its workspace from the route, so
      // mounting it against a URL that names a different workspace (or none) scopes its first
      // fetch to the wrong one. `resolved !== undefined` cannot cover this: `resolved` is a
      // decided string here, and it is exactly the URL that has not caught up.
      routerFeedsBack = false;
      readCached.mockReturnValue("acme");
      prefsGet.mockResolvedValue({ slug: "acme" });

      render(<Shell />);
      await waitFor(() => expect(replace).toHaveBeenCalledWith("/acme", { scroll: false }));
      expect(screen.getByTestId("picker")).toHaveAttribute("data-selected", "acme");
      expect(screen.queryByTestId("feature")).toBeNull();

      // Let the URL land. Same resolution, now agreed with — and only now does it mount.
      await act(async () => {
        liveSetSlug("acme");
        await new Promise((r) => setTimeout(r, 0));
      });
      expect(screen.getByTestId("feature")).toBeInTheDocument();
    },
  );

  it("empty workspace list — the empty-state hint, no replace, no PUT", async () => {
    list.mockResolvedValue([]);
    render(<Shell />);
    await waitFor(() => expect(screen.getByText(/no workspaces/i)).toBeInTheDocument());
    expect(screen.queryByTestId("feature")).toBeNull();
    expect(replace).not.toHaveBeenCalled();
    expect(prefsPut).not.toHaveBeenCalled();
  });

  it("[max review, finding 7] a FAILED workspace list says so, instead of a permanent blank", async () => {
    // The failure has no other exit. A rejected list leaves `items` null, resolution never leaves
    // `undefined`, the children never mount and the empty-state hint never fires — so without this
    // branch the page is a chooser with nothing in it, above nothing, forever, on every one of the
    // sites that mount this shell.
    list.mockRejectedValue(new Error("offline"));
    render(<Shell />);
    await waitFor(() => expect(screen.getByText(/couldn't load your workspaces/i)).toBeInTheDocument());
    // And it says the RIGHT thing: "no workspaces yet" is a claim about this user's account, which
    // a failed request is in no position to make.
    expect(screen.queryByText(/no workspaces yet/i)).toBeNull();
    expect(screen.queryByTestId("feature")).toBeNull();
    expect(replace).not.toHaveBeenCalled();
    expect(prefsPut).not.toHaveBeenCalled();
  });

  it("[max review, finding 7] a list still LOADING says nothing — the hint is not a spinner", async () => {
    // `workspaces === null` alone would put the failure hint on screen for the whole of every
    // normal load, since a list that has not arrived yet is null too. Both halves of the gate are
    // load-bearing; this is the `error !== null` half.
    list.mockReturnValue(new Promise(() => {}));
    render(<Shell />);
    await act(async () => {
      await new Promise((r) => setTimeout(r, 0));
    });
    expect(screen.queryByText(/couldn't load your workspaces/i)).toBeNull();
    expect(screen.queryByTestId("feature")).toBeNull();
  });

  it("[max review, finding 7] a failed REFETCH keeps its page — no error banner over live rows", async () => {
    // The `workspaces === null` half. Rows are already on screen when a request fails: the real
    // hook paints from its module cache on a mount and revalidates behind it, so this is the
    // ordinary second visit with the network gone. The list the user is looking at is still good,
    // and replacing it with an apology would be a worse answer than the slightly stale one it
    // already has.
    //
    // Driven by the seed rather than by changing the cache key, which is what this used to do: a
    // site cannot change that key any more, so a test that did would be exercising a state the
    // shell can no longer be in.
    seedRows = WORKSPACES;
    list.mockRejectedValue(new Error("offline"));
    render(<Shell workspaceSlug="acme" />);
    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
    await act(async () => {
      await new Promise((r) => setTimeout(r, 0));
    });

    expect(screen.queryByText(/couldn't load your workspaces/i)).toBeNull();
    expect(screen.getByRole("button", { name: "Acme" })).toBeInTheDocument();
    expect(screen.getByTestId("feature")).toBeInTheDocument();
  });

  it("seeds the workspace at the host's own base when one is declared", async () => {
    // research's `/<slug>` is a PUBLIC author page; its gated surface is `/<slug>/home`. Seeding
    // the bare workspace would land a signed-in visitor on the public page, which is the one
    // outcome `/home` exists to prevent.
    readCached.mockReturnValue("acme");
    render(<Shell workspaceHref={(slug) => `/${slug}/home`} />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith("/acme/home", { scroll: false }));
    // `scopedBase` is NOT the declared base: it stays the workspace itself, and the host appends
    // its own surfaces. A shell that conflated the two would give the feature `/acme/home` here
    // and every link it builds would gain a second `/home`.
    await waitFor(() =>
      expect(screen.getByTestId("feature").dataset.scopedBase).toBe("/acme"),
    );
  });

  it("still seeds the bare workspace when the host declares no base", async () => {
    readCached.mockReturnValue("acme");
    render(<Shell />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith("/acme", { scroll: false }));
  });
});

describe("SiteHomeShell picker mount", () => {
  it("[round 5, matrix row s03] a picked workspace navigates from the CURRENT path", async () => {
    // This row used to be about `basePath`: the shell took a base, `onSelect` closed over it, and
    // nothing pinned that dependency — emptying the array left 36 green, because every other test
    // mounted one shell at one base. The base is gone (every site's workspace is its first
    // segment), and the same staleness now lives on `pathname`, which changes under a mounted
    // shell on every navigation rather than only across mounts. So the assertion moves with it.
    livePathname = "/mine";
    const { rerender } = render(<Shell workspaceSlug="mine" />);
    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());

    livePathname = "/mine/services/svc_1";
    rerender(<Shell workspaceSlug="mine" />);
    fireEvent.click(screen.getByRole("button", { name: "Acme" }));

    expect(push).toHaveBeenCalledWith("/acme/services/svc_1", { scroll: false });
  });

  it("renders ONE picker, in a bar, from one list", async () => {
    const { container } = render(<Shell workspaceSlug="mine" />);
    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());

    // One picker at every width — no portal, no second copy, so there is no arrangement in which
    // a user sees two or (as the portal could) none. The count is the assertion: the shell used
    // to render <WorkspacePicker> from two separate JSX expressions whose props could drift.
    const pickers = screen.getAllByTestId("picker");
    expect(pickers).toHaveLength(1);
    expect(list).toHaveBeenCalledTimes(1);

    // It lives in the bar, with no visible "Workspace" word beside it — the trigger reads as the
    // workspace's name, and its own `ariaLabel="Workspace"` names it to assistive tech.
    const toolbar = container.querySelector(".adh-home__toolbar");
    expect(toolbar).not.toBeNull();
    expect(toolbar).toContainElement(pickers[0]!);
    expect(toolbar!.querySelector(".adh-home__toolbar-label")).toBeNull();

    // And it is wired: all three props reach the one mount.
    expect(pickers[0]!).toHaveAttribute("data-selected", "mine");
    expect(
      within(pickers[0]!)
        .getAllByRole("button")
        .map((b) => b.textContent),
    ).toEqual(["My Workspace", "Acme"]);
    fireEvent.click(within(pickers[0]!).getByRole("button", { name: "Acme" }));
    expect(push).toHaveBeenCalledWith("/acme", { scroll: false });
  });

  it("selecting a workspace pushes the URL, and the settled effect writes the cache and the server", async () => {
    render(<Shell workspaceSlug="mine" />);
    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
    fireEvent.click(screen.getByRole("button", { name: "Acme" }));
    // onSelect itself does nothing but navigate — no synchronous write.
    expect(push).toHaveBeenCalledWith("/acme", { scroll: false });
    await waitFor(() => expect(writeCached).toHaveBeenCalledWith("acme"));
    await waitFor(() => expect(prefsPut).toHaveBeenCalledWith({ slug: "acme" }));
  });

  // Finding 4: the old version of this test could only fail if `.catch(() => {})` were deleted
  // from the OTHER test's subject (B3, now above) — its own three assertions duplicated B3's,
  // and its comment ("an unhandled rejection here would fail the run") was false in this
  // vitest/jsdom config. A `process.on("unhandledRejection")` listener is the review's suggested
  // fix, but it only fires for a genuinely un-instrumented promise — a rejection produced by
  // `prefsPut.mockRejectedValue(...)` (a vi.fn()) never reaches it, since vi.fn()'s own
  // `mock.results` bookkeeping attaches a handler to whatever it returns before Node's microtask
  // queue would otherwise call it unhandled. That's why `put`'s return value above comes from
  // `prefsPutResult`, a plain function outside any vi.fn() — set here to a genuinely rejecting
  // promise, so this listener is a real guard on the production `.catch()`, not a vacuous one.
  it("a failed PUT is silent — the cache still carries the choice, and nothing throws unhandled", async () => {
    prefsPutResult = () => Promise.reject(new Error("offline"));
    const unhandled: unknown[] = [];
    const onUnhandled = (reason: unknown) => unhandled.push(reason);
    process.on("unhandledRejection", onUnhandled);
    try {
      render(<Shell workspaceSlug="mine" />);
      await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
      fireEvent.click(screen.getByRole("button", { name: "Acme" }));
      await waitFor(() => expect(writeCached).toHaveBeenCalledWith("acme"));
      // Flush the rejected PUT's microtask queue before checking for an unhandled rejection.
      await new Promise((r) => setTimeout(r, 0));
      expect(unhandled).toHaveLength(0);
    } finally {
      process.off("unhandledRejection", onUnhandled);
    }
  });
});

// Switching workspace KEEPS what you were looking at. A feature site's HTDV holds no selected
// path of its own — the stack IS the segments below the workspace, which `model.parse` reads — so
// these cases are the whole of that feature: which segments move, which do not, and which
// navigation carries them at all.
describe("SiteHomeShell workspace switch carries the selection", () => {
  it("moves every segment below the workspace onto the new one", async () => {
    livePathname = "/mine/services/svc_1";
    render(<Shell workspaceSlug="mine" />);
    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());

    fireEvent.click(screen.getByRole("button", { name: "Acme" }));
    expect(push).toHaveBeenCalledWith("/acme/services/svc_1", { scroll: false });
  });

  it("finds the workspace by POSITION, so a deeper segment spelled like the slug is carried", async () => {
    // The reason `workspacePathTail` drops the first segment rather than searching the path for
    // the slug: an entity id, a feature or a sub-route may be spelled exactly like the workspace.
    // A search finds the wrong one — here it would cut at the LAST "mine" and carry nothing.
    //
    // A sibling case lived here while three sites mounted their workspace under `/home/`: a base
    // above the workspace had to be kept above it, not carried as selection. There is no base to
    // get wrong now — the workspace is the first segment on all 38 — so what is left is position,
    // which is this.
    livePathname = "/mine/services/mine";
    render(<Shell workspaceSlug="mine" />);
    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());

    fireEvent.click(screen.getByRole("button", { name: "Acme" }));
    expect(push).toHaveBeenCalledWith("/acme/services/mine", { scroll: false });
  });

  it("carries nothing when the workspace IS the whole path", async () => {
    livePathname = "/mine";
    render(<Shell workspaceSlug="mine" />);
    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());

    fireEvent.click(screen.getByRole("button", { name: "Acme" }));
    expect(push).toHaveBeenCalledWith("/acme", { scroll: false });
  });

  it("carries NOTHING off an unreachable workspace — the deep link lands on the profile, not re-aimed", async () => {
    // This case used to assert the shape of a REPAIR: `/zzz/services/svc_1` replaced to `/acme`,
    // the tail dropped so the user was not deep-linked into a page they never asked for off a slug
    // the list does not contain. There is no repair now — the whole URL lands on `zzz`'s own
    // profile — but the harm it was written against is the same one and still worth a row, because
    // a carry is exactly the bug that would reappear if the profile branch were ever softened back
    // into a redirect. So the assertion is that NOTHING navigates: not the workspace, and
    // certainly not the tail.
    readCached.mockReturnValue("acme");
    livePathname = "/zzz/services/svc_1";
    renderReachable({ workspaceSlug: "zzz" });
    await waitFor(() => expect(screen.getByTestId("profile-fallback")).toBeInTheDocument());
    expect(screen.getByTestId("profile-fallback")).toHaveAttribute("data-slug", "zzz");
    expect(replace).not.toHaveBeenCalled();
    expect(push).not.toHaveBeenCalled();
  });
});

// The child contract itself. `children` is a FUNCTION, and these are the two properties that
// choice buys — neither of which a ReactNode child could have had.
describe("SiteHomeShell child scope", () => {
  // A third test lived here and was deleted before it ever shipped: "hands the RESOLVED
  // workspace, not the segment that was in the URL". It could not fail for that reason. The gate
  // above the call is `resolved === workspaceSlug`, so inside it the two are the same string and
  // no mutation can tell them apart; dropping the gate — the only way to separate them — is
  // already caught by "children stay unmounted while the URL still disagrees" above. Mutation
  // testing is what surfaced it: the mutation the name described turned a DIFFERENT test red and
  // left this one green.

  it("rebuilds the scoped base when the workspace changes", async () => {
    // The one assertion that fails if `scopedBase` is ever frozen at its first value — which is
    // the shape a literal, a mount-time constant or a `useMemo([])` all collapse to, and none of
    // them would fail a single-workspace test.
    livePathname = "/mine";
    render(<Shell workspaceSlug="mine" />);
    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
    expect(screen.getByTestId("feature")).toHaveAttribute("data-scoped-base", "/mine");

    fireEvent.click(screen.getByRole("button", { name: "Acme" }));
    await waitFor(() =>
      expect(screen.getByTestId("feature")).toHaveAttribute("data-scoped-base", "/acme"),
    );
  });

  it("never CALLS children before a workspace resolves", async () => {
    // The stronger form of "holds children until resolved" at the top of this file: that one can
    // only observe that nothing reached the DOM, which a node child rendered inside a hidden
    // branch would also satisfy. Counting calls proves the site's `render` — and therefore its
    // `parse`, and any list request its feature fires on mount — never runs unscoped.
    let settleList: (w: typeof WORKSPACES) => void = () => {};
    list.mockReturnValue(new Promise((r) => (settleList = r)));
    const child = vi.fn(() => <div data-testid="feature">the feature</div>);

    render(
      <SiteHomeShell workspaceSlug="acme">{child}</SiteHomeShell>,
    );

    // Several renders happen here — the prefs GET settles, state lands — with no workspace list.
    await new Promise((r) => setTimeout(r, 0));
    expect(child).not.toHaveBeenCalled();

    settleList(WORKSPACES);
    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
    expect(child).toHaveBeenCalledWith({
      workspaceSlug: "acme",
      scopedBase: "/acme",
      workspace: WORKSPACES[1],
    });
  });

  it("hands over the resolved workspace's ROW, so a feature can read its kind without refetching", async () => {
    // The reason `workspace` is on the scope at all: a surface whose wording differs between a
    // personal workspace and an organization (integrations' "My" vs "Org" destination) reads
    // `kind` here. Asserting the KIND rather than the identity is what makes this fail if the
    // shell ever hands over the first row, or the row the URL segment named, instead of the row
    // it actually resolved — `acme` is the second row and the only organization in the list.
    render(<Shell workspaceSlug="acme" />);

    await waitFor(() => expect(screen.getByTestId("feature")).toBeInTheDocument());
    expect(screen.getByTestId("feature")).toHaveAttribute("data-kind", "organization");
  });
});
