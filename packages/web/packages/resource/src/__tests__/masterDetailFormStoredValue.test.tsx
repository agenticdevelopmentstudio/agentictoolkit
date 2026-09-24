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
