/**
 * The stored-value exemption, both halves: what `useMasterDetailForm` tells `validate` the record
 * was STORED with, and `unchangedFromStored`, the one test every validator applies to it.
 *
 * They are one contract. The helper exempts nothing when the stored value is null, and the hook
 * passes null while creating. The hook used to pass `blank()` there instead, a blank draft
 * "matched" it, and userValidate waived "Email is required." for a brand-new user — the validator
 * shape below is userValidate's, reduced to the one field that shows it.
 */
import { act, renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { unchangedFromStored } from "../master-detail/unchangedFromStored";
import {
  useMasterDetailForm,
  type MasterDetailFormConfig,
} from "../master-detail/useMasterDetailForm";

interface Row {
  id: string;
  name: string;
  email: string;
}
type Draft = { name: string; email: string };

const NAME_REQUIRED = "Name is required.";
const EMAIL_REQUIRED = "Email is required.";
// `sso` is what the backend writes for an SSO-provisioned user: a NULL email, read back as "".
const SSO_USER: Row = { id: "sso", name: "SSO User", email: "" };
const ROWS: Row[] = [SSO_USER, { id: "r1", name: "Row One", email: "a@b.co" }];

/** userValidate's shape: an email the record was stored with is exempt from every email rule. */
function exemptingValidate(d: Draft, _others: Row[], base: Draft | null): string | null {
  if (!d.name.trim()) return NAME_REQUIRED;
  if (unchangedFromStored(d.email, base?.email)) return null;
  return d.email.trim() ? null : EMAIL_REQUIRED;
}

function makeConfig(
  overrides: Partial<MasterDetailFormConfig<Row, Draft>> = {},
): MasterDetailFormConfig<Row, Draft> {
  return {
    items: ROWS,
    getId: (r) => r.id,
    blank: () => ({ name: "", email: "" }),
    toInput: (r) => ({ name: r.name, email: r.email }),
    validate: exemptingValidate,
    differs: (a, b) => a.name !== b.name || a.email !== b.email,
    create: async (input) => ({ id: "r2", ...input }),
    update: async (id, input) => ({ id, ...input }),
    refresh: () => {},
    createLabel: "New row",
    ...overrides,
  };
}

describe("useMasterDetailForm — `validate` is told what was STORED", () => {
  it("passes null while creating, so a create grandfathers nothing", () => {
    const validate = vi.fn(exemptingValidate);
    const { result } = renderHook(() => useMasterDetailForm(makeConfig({ validate })));
    act(() => result.current.actions.onCreate());
    act(() => result.current.onChange({ name: "Ada", email: "" }));

    // With `blank()` as the stored value, "" matched "" and this was null: Save lit up for a new
    // user with no email at all.
    expect(result.current.actions.blockedReason).toBe(EMAIL_REQUIRED);
    expect(result.current.actions.canSave).toBe(false);
    expect(validate).toHaveBeenCalled();
    for (const call of validate.mock.calls) expect(call[2]).toBeNull();
  });

  it("refuses the same blank create in save() — the second call site", async () => {
    const create = vi.fn(async (input: Draft) => ({ id: "r2", ...input }));
    const validate = vi.fn(exemptingValidate);
    const { result } = renderHook(() => useMasterDetailForm(makeConfig({ create, validate })));
    act(() => result.current.actions.onCreate());
    act(() => result.current.onChange({ name: "Ada", email: "" }));

    // Straight to `save()`, as the exit guard's Save does — it does not go through `canSave`.
    await act(async () => {
      expect(await result.current.actions.onSave()).toBe(false);
    });
    expect(create).not.toHaveBeenCalled();
    expect(result.current.error).toBe(EMAIL_REQUIRED);
    for (const call of validate.mock.calls) expect(call[2]).toBeNull();
  });

  it("passes the selected record's stored input while editing", () => {
    const validate = vi.fn(exemptingValidate);
    const { result } = renderHook(() => useMasterDetailForm(makeConfig({ validate })));
    act(() => result.current.select("sso"));
    act(() => result.current.onChange({ name: "Renamed", email: "" }));

    // The SSO user's untouched empty email is still exempt, so a rename can be saved.
    expect(validate).toHaveBeenLastCalledWith(
      { name: "Renamed", email: "" },
      [ROWS[1]],
      { name: SSO_USER.name, email: SSO_USER.email },
    );
    expect(result.current.actions.blockedReason).toBeNull();
    expect(result.current.actions.canSave).toBe(true);
  });

  it("measures the stored value from what was LOADED, not from the draft", () => {
    const { result } = renderHook(() => useMasterDetailForm(makeConfig()));
    act(() => result.current.select("r1"));
    // Clearing an email the record HAS is an edit, and an edit is held to the rules.
    act(() => result.current.onChange({ name: "Row One", email: "" }));
    expect(result.current.actions.blockedReason).toBe(EMAIL_REQUIRED);
  });
});

describe("unchangedFromStored", () => {
  it("is false when nothing is stored (a create), whatever the value", () => {
    expect(unchangedFromStored("", null)).toBe(false);
    expect(unchangedFromStored("", undefined)).toBe(false);
    expect(unchangedFromStored("participants", undefined)).toBe(false);
  });

  it("trims both sides", () => {
    expect(unchangedFromStored("  participants ", "participants")).toBe(true);
    expect(unchangedFromStored("participants", " participants  ")).toBe(true);
  });

  it("does not fold case — re-casing a value is an edit", () => {
    expect(unchangedFromStored("Sprint 12", "sprint 12")).toBe(false);
  });

  it("treats an empty value on an empty stored record as untouched", () => {
    // The SSO user stored with a NULL email, read back as "".
    expect(unchangedFromStored("", "")).toBe(true);
    expect(unchangedFromStored("   ", "")).toBe(true);
  });

  it("is false for a changed value", () => {
    expect(unchangedFromStored("a@b.co", "")).toBe(false);
    expect(unchangedFromStored("", "a@b.co")).toBe(false);
  });
});

// G14: the hook itself does NO grandfathering any more — `reasonFor` just returns
// `config.validate(d, others, stored)` (see the comment on it in useMasterDetailForm.ts). A
// validator that never calls `unchangedFromStored` on its own fields gets none, even when the
// stored record already fails one of its rules (Mike, 2026-09-25). This replaces a block that used
// to assert the OLD hook-level behaviour (waiving a reason whose MESSAGE matched the stored
// record's) — that comparison is exactly what G14 found broken, for two reasons proven below.
describe("useMasterDetailForm — a validator that never exempts itself gets no exemption", () => {
  const SLUG = "Use a dotted identifier.";
  /** A strict format rule with no stored-value exemption of its own. */
  function strictValidate(d: Draft): string | null {
    if (!d.name.trim()) return NAME_REQUIRED;
    return d.email.includes(".") ? null : SLUG;
  }
  const LEGACY: Row = { id: "legacy", name: "Legacy", email: "participants" };

  it("blocks Save on an edit to another field, because the validator never exempted the legacy email", () => {
    const { result } = renderHook(() =>
      useMasterDetailForm(makeConfig({ items: [LEGACY], validate: strictValidate })),
    );
    act(() => result.current.select("legacy"));
    act(() => result.current.onChange({ name: "Renamed", email: "participants" }));
    // The OLD hook-level grandfathering used to waive this: `config.validate(stored, ...)`
    // reproduced the identical SLUG text, so the hook cleared it. `reasonFor` no longer runs that
    // second call at all, so a validator that wants this leniency has to say so itself.
    expect(result.current.actions.blockedReason).toBe(SLUG);
    expect(result.current.actions.canSave).toBe(false);
  });

  it("reports a DIFFERENT invalid value even though it produces the identical message text — the G14 (b) bug", () => {
    // The old bug compared MESSAGES, not values: two different bad emails that both fail the
    // "needs a dot" rule produced the same SLUG text, and the hook waived the second one as though
    // it were the untouched original, even though it is a brand-new (and still invalid) edit.
    const { result } = renderHook(() =>
      useMasterDetailForm(makeConfig({ items: [LEGACY], validate: strictValidate })),
    );
    act(() => result.current.select("legacy"));
    act(() =>
      result.current.onChange({ name: "Legacy", email: "totally-different-but-still-bad" }),
    );
    expect(result.current.actions.blockedReason).toBe(SLUG);
    expect(result.current.actions.canSave).toBe(false);
  });

  it("still blocks a NEW problem the edit introduces", () => {
    const { result } = renderHook(() =>
      useMasterDetailForm(makeConfig({ items: [LEGACY], validate: strictValidate })),
    );
    act(() => result.current.select("legacy"));
    act(() => result.current.onChange({ name: "", email: "participants" }));
    expect(result.current.actions.blockedReason).toBe(NAME_REQUIRED);
    expect(result.current.actions.canSave).toBe(false);
  });

  it("grandfathers nothing on create", () => {
    const { result } = renderHook(() =>
      useMasterDetailForm(makeConfig({ items: [LEGACY], validate: strictValidate })),
    );
    act(() => result.current.actions.onCreate());
    act(() => result.current.onChange({ name: "New", email: "participants" }));
    expect(result.current.actions.blockedReason).toBe(SLUG);
  });
});

// The pattern the fix moved grandfathering INTO: a validator calls `unchangedFromStored` on the
// ONE field its own rule is about, and SKIPS that rule's check entirely when the field is
// untouched — rather than running the rule, getting a message, and comparing message text after
// the fact (which is what let one shadowed rule hide another — the G14 (a) bug). Because the skip
// happens before the rule runs, a LATER rule in the same validator is never shadowed by an earlier
// one's grandfathered failure (Mike, 2026-09-25).
describe("useMasterDetailForm — a validator that grandfathers itself, rule by rule", () => {
  const RULE_A = "A must be lowercase letters only.";
  const RULE_B = "B must be lowercase letters only.";
  type ABDraft = { a: string; b: string };
  interface ABRow extends ABDraft {
    id: string;
  }

  function selfGrandfatheringValidate(
    d: ABDraft,
    _others: ABRow[],
    base: ABDraft | null,
  ): string | null {
    if (!unchangedFromStored(d.a, base?.a) && !/^[a-z]*$/.test(d.a)) return RULE_A;
    if (!/^[a-z]*$/.test(d.b)) return RULE_B;
    return null;
  }

  // Stored with an invalid `a` (predates the format rule) and a valid `b`.
  const LEGACY: ABRow = { id: "legacy", a: "BAD1", b: "ok" };

  function abConfig(
    overrides: Partial<MasterDetailFormConfig<ABRow, ABDraft>> = {},
  ): MasterDetailFormConfig<ABRow, ABDraft> {
    return {
      items: [LEGACY],
      getId: (r) => r.id,
      blank: () => ({ a: "", b: "" }),
      toInput: (r) => ({ a: r.a, b: r.b }),
      validate: selfGrandfatheringValidate,
      differs: (x, y) => x.a !== y.a || x.b !== y.b,
      create: async (input) => ({ id: "new", ...input }),
      update: async (id, input) => ({ id, ...input }),
      refresh: () => {},
      createLabel: "New row",
      ...overrides,
    };
  }

  it("(a) still reports a LATER rule the edit breaks, even though an EARLIER rule is grandfathered", () => {
    const { result } = renderHook(() => useMasterDetailForm(abConfig()));
    act(() => result.current.select("legacy"));
    // `a` is untouched (still the legacy "BAD1") — exempt, rule A never runs. `b` is edited to
    // something invalid. Under the OLD hook-level comparison, rule A's failure (unchanged from
    // stored) would have masked rule B ever being reached at all — that's exactly the bug: rule B's
    // NEW problem is reported here, not hidden behind rule A's old one.
    act(() => result.current.onChange({ a: "BAD1", b: "BAD2" }));
    expect(result.current.actions.blockedReason).toBe(RULE_B);
    expect(result.current.actions.canSave).toBe(false);
  });

  it("(c) exempts the untouched legacy field when a DIFFERENT field is edited to something valid", () => {
    const { result } = renderHook(() => useMasterDetailForm(abConfig()));
    act(() => result.current.select("legacy"));
    // `a` stays exactly as stored ("BAD1"); `b` changes but still satisfies its own rule. Save is
    // enabled despite the legacy `a` never having satisfied rule A.
    act(() => result.current.onChange({ a: "BAD1", b: "changed" }));
    expect(result.current.actions.blockedReason).toBeNull();
    expect(result.current.actions.canSave).toBe(true);
  });

  it("still blocks a change TO the grandfathered field that is itself invalid", () => {
    const { result } = renderHook(() => useMasterDetailForm(abConfig()));
    act(() => result.current.select("legacy"));
    // `a` is now genuinely edited (not just re-sent unchanged) to a new, still-invalid value — the
    // exemption is for the untouched legacy value, not a blanket pass on the field forever.
    act(() => result.current.onChange({ a: "BAD3", b: "ok" }));
    expect(result.current.actions.blockedReason).toBe(RULE_A);
    expect(result.current.actions.canSave).toBe(false);
  });
});
