// The drift gate for `@agentic-toolkit/data`'s profile wire shapes — the thing that package's
// header could not do on its own. It transcribes the backend's rows by hand and CITES its
// sources in a comment, and a citation is not a check: a backend column rename regenerates
// ./schema.ts, every consumer still compiles against the hand-written interface, and the field
// simply reads `undefined` in the Profile editor and the public UserCard. Nothing errors, on
// any site.
//
// IT LIVES HERE, NOT THERE, and that is the whole reason this file moved. `data` is a PORTABLE
// package, and `scripts/check_boundaries.py` (adh runs it as verify_toolkit_boundary.py) refuses
// any import of the adh vocabulary tier from one — the direction is one-way by design, because
// such an import resolves fine inside adh's workspace and fails only in a consumer. A gate is
// not a reason to open a hole in that: this package IS the adh tier, it already devDepends on
// portable siblings (`crud`, `api-explorer`), and measuring a transcription needs both sides
// regardless of which one holds the file. So the dependency points the sanctioned way and the
// guard needs no exemption.
//
// Consequence worth knowing: `moduleResolution: "bundler"` with no `customConditions` takes
// `data`'s `types` condition, so the shapes below are read from its BUILT `dist/*.d.ts`, not
// from `src/`. That is fail-closed rather than silent — an unbuilt `data` makes this file fail
// to resolve — and it does not weaken what the gate is for: a backend rename regenerates
// ./schema.ts, which is read straight from source here, so it reddens on the same run.
//
// Run by `tsc --noEmit` (`pnpm lint` / `pnpm test`), not by vitest: `.test-d.ts` is outside
// vitest's include glob, exactly as ./index.test-d.ts is. Every entry in `Checks` must be
// literally `true`, or `Expect<… extends true>` fails and the package stops type-checking.
import type { RequestBody, SuccessBody } from "./index";
import type {
  SocialLink,
  SocialLinkWrite,
  Address,
  AddressWrite,
  PrivacyGrant,
  PrivacyTargetTable,
  UsageRow,
} from "@agentic-toolkit/data/profile";

// ── assertion utilities (same set as ./index.test-d.ts) ──────────────────────────────────
type Expect<T extends true> = T;
type Equal<A, B> =
  (<T>() => T extends A ? 1 : 2) extends <T>() => T extends B ? 1 : 2 ? true : false;
type Extends<A, B> = A extends B ? true : false;
type IsNever<T> = [T] extends [never] ? true : false;
type IsAny<T> = 0 extends 1 & T ? true : false;

/** Keys the client would SEND that the backend does not accept — the write-side rename check.
 *  Plain assignability cannot see these: excess-property checking applies to fresh object
 *  literals, not to one declared type measured against another. */
type UnknownKeys<Written, Wire> = Exclude<keyof Written, keyof Wire>;

// ── what the backend actually declares ───────────────────────────────────────────────────
type WireSocialLink = SuccessBody<"/content/social-links", "get">[number];
type WireAddress = SuccessBody<"/content/addresses", "get">[number];
type WirePrivacyGrant = SuccessBody<"/account/privacy", "get">["items"][number];
type WireUsageRow = SuccessBody<"/usage/summary", "get">["rows"][number];
type WireSocialLinkCreate = RequestBody<"/content/social-links", "post">;
type WireAddressCreate = RequestBody<"/content/addresses", "post">;

// Exported so every assertion is referenced and none can be dead-stripped.
export type Checks = [
  // ── FAIL TO CHECK ───────────────────────────────────────────────────────────────────
  // A mistyped path resolves to `never`, and `never extends anything` is TRUE — so every
  // assertion below would pass while measuring nothing. `any` swallows them the same way.
  // Both are refused first, for the same reason the Python guards in adh-tools' sites/scripts refuse
  // an empty scan.
  Expect<Equal<IsNever<WireSocialLink>, false>>,
  Expect<Equal<IsNever<WireAddress>, false>>,
  Expect<Equal<IsNever<WirePrivacyGrant>, false>>,
  Expect<Equal<IsNever<WireUsageRow>, false>>,
  Expect<Equal<IsNever<WireSocialLinkCreate>, false>>,
  Expect<Equal<IsNever<WireAddressCreate>, false>>,
  Expect<Equal<IsAny<WireSocialLink>, false>>,
  Expect<Equal<IsAny<WireUsageRow>, false>>,

  // ── READ SIDE ───────────────────────────────────────────────────────────────────────
  // Everything the backend sends must satisfy the transcription: a renamed, removed or
  // retyped column stops the generated row from being assignable, and this goes red.
  //
  // The direction is deliberate. The reverse — requiring the transcription to name every
  // column — would fail on a purely ADDITIVE backend change, which is not a client defect:
  // this file is a narrowing VIEW of the row, and a field it does not read cannot come out
  // `undefined` anywhere.
  Expect<Extends<WireSocialLink, SocialLink>>,
  Expect<Extends<WireAddress, Address>>,
  Expect<Extends<WirePrivacyGrant, PrivacyGrant>>,
  Expect<Extends<WireUsageRow, UsageRow>>,

  // `UsageRow` is the whole projection rather than a view of a row, so it is pinned EXACTLY:
  // a new field on the usage summary is a field the usage page is meant to show.
  Expect<Equal<WireUsageRow, UsageRow>>,

  // ── THE ONE DELIBERATE DIVERGENCE ───────────────────────────────────────────────────
  // `PrivacyTargetTable` widens the generated enum to `string` on purpose (see `data`'s
  // src/profile/wire.ts:
  // a client that hard-coded the members would refuse a target the backend later adds). That
  // is why the read-side check above runs one way only, and pinning the asymmetry here keeps
  // it a stated decision — if someone narrows the alias back to the union, this entry flips
  // and says so, instead of the widening quietly disappearing.
  Expect<Equal<PrivacyTargetTable, string>>,
  Expect<Equal<Extends<PrivacyGrant, WirePrivacyGrant>, false>>,

  // ── WRITE SIDE ──────────────────────────────────────────────────────────────────────
  // Every field the editor sends must still be a column the backend accepts. A rename shows
  // up as a leftover key here — a create that silently drops the value otherwise.
  Expect<Equal<UnknownKeys<SocialLinkWrite, WireSocialLinkCreate>, never>>,
  Expect<Equal<UnknownKeys<AddressWrite, WireAddressCreate>, never>>,
  Expect<Extends<SocialLinkWrite, WireSocialLinkCreate>>,
  Expect<Extends<AddressWrite, WireAddressCreate>>,
];

// The write shapes are a SUBSET on purpose — the server owns identity, tenancy, ownership and
// the sync stamps, so the editor must not be able to name them. `@ts-expect-error` is itself a
// tsc error when the line compiles, so each of these fails the build if a server-managed column
// ever becomes writable from here without the decision being made explicitly.
export const guardedColumns = (): void => {
  // @ts-expect-error — `id` is server-managed; a client must not send one.
  const badLink: SocialLinkWrite = { platform: "x", url: "u", handle: "h", id: "s1" };
  const badAddress: AddressWrite = {
    label: "Home",
    line1: "1",
    line2: "",
    city: "c",
    region: "r",
    postalCode: "p",
    country: "US",
    // A directive suppresses only the line DIRECTLY below it, and an excess property in a
    // multi-line literal is reported at the property — so this one sits here, not above the
    // `const`, where it would report as unused and prove nothing.
    // @ts-expect-error — `ownerId` is decided by the `?workspace=` scope, never by the body.
    ownerId: "o1",
  };
  void badLink;
  void badAddress;
};
