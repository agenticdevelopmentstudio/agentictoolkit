import { describe, it, expect } from "vitest";
import {
  bodyFrom,
  count,
  draftFrom,
  isTierFormDirty,
  optionalCount,
  tierChanges,
  tierFormBlockedReason,
  type TierDraft,
} from "../tier-form";

const TIER = {
  id: "t-free",
  slug: "free",
  name: "Free",
  isDefault: true,
  isActive: true,
  quotaEnforced: false,
  quotaRequests: 1000,
  quotaBytes: null,
  quotaTokens: null,
  quotaCostMicros: null,
  quotaPeriodDays: 30,
  rateCapacity: 60,
  rateRefillTokens: 1,
  rateRefillSeconds: 1,
} as never;

const base = (): TierDraft => draftFrom(TIER);

describe("draftFrom — the row as editable text", () => {
  it("renders a null cap as the empty string, never as 0", () => {
    const draft = base();
    expect(draft.quotaBytes).toBe("");
    expect(draft.quotaRequests).toBe("1000");
  });

  it("carries the enforced flag through as a boolean", () => {
    expect(base().quotaEnforced).toBe(false);
  });
});

describe("count — a required whole number", () => {
  it("parses a positive integer", () => {
    expect(count("30", "Period (d)")).toBe(30);
  });

  it.each(["", "  ", "0", "-1", "1.5", "abc"])("refuses %o", (raw) => {
    expect(() => count(raw, "Period (d)")).toThrow(/whole number of 1 or more/);
  });

  it("names the field it is complaining about", () => {
    expect(() => count("", "Burst")).toThrow(/^Burst /);
  });
});

describe("optionalCount — a cap that may be blank", () => {
  it("reads blank as UNCAPPED (null), which is not the same as zero", () => {
    expect(optionalCount("", "Bytes")).toBeNull();
    expect(optionalCount("   ", "Bytes")).toBeNull();
  });

  // Zero is a legal, meaningful cap: it refuses everything. A gate that rejected it would make
  // "this tier gets nothing" unexpressible.
  it("accepts 0", () => {
    expect(optionalCount("0", "Bytes")).toBe(0);
  });

  it.each(["-1", "1.5", "1,000", "abc"])("refuses %o", (raw) => {
    expect(() => optionalCount(raw, "Bytes")).toThrow(/whole number of 0 or more/);
  });
});

describe("tierChanges — only what the operator touched", () => {
  it("is empty for an untouched draft", () => {
    expect(tierChanges(base(), base())).toEqual({});
  });

  it("carries one edited field and nothing else", () => {
    const form = { ...base(), quotaRequests: "2000" };
    expect(tierChanges(form, base())).toEqual({ quotaRequests: "2000" });
  });

  it("ignores a change that is only surrounding whitespace", () => {
    const form = { ...base(), quotaRequests: "  1000  " };
    expect(tierChanges(form, base())).toEqual({});
  });

  it("carries the enforced flag when it flips", () => {
    const form = { ...base(), quotaEnforced: true };
    expect(tierChanges(form, base())).toEqual({ quotaEnforced: true });
  });

  // Clearing a cap is a real edit — "" against a stored number means "make this uncapped".
  it("treats clearing a cap as a change", () => {
    const form = { ...base(), quotaRequests: "" };
    expect(tierChanges(form, base())).toEqual({ quotaRequests: "" });
  });
});

describe("isTierFormDirty", () => {
  it("is false for an untouched draft", () => {
    expect(isTierFormDirty(base(), base())).toBe(false);
  });

  it("is true once any numeric field differs", () => {
    expect(isTierFormDirty({ ...base(), rateCapacity: "120" }, base())).toBe(true);
  });

  it("is true once Enforced flips", () => {
    expect(isTierFormDirty({ ...base(), quotaEnforced: true }, base())).toBe(true);
  });
});

describe("bodyFrom — the PUT patch", () => {
  it("is empty when nothing changed", () => {
    expect(bodyFrom({})).toEqual({});
  });

  it("sends a cleared cap as null, so the backend un-caps it", () => {
    expect(bodyFrom({ quotaRequests: "" })).toEqual({ quotaRequests: null });
  });

  it("sends only the keys it was given", () => {
    expect(bodyFrom({ quotaTokens: "5000", quotaEnforced: true })).toEqual({
      quotaTokens: 5000,
      quotaEnforced: true,
    });
  });

  it("throws on a required field that was blanked", () => {
    expect(() => bodyFrom({ quotaPeriodDays: "" })).toThrow(/Period \(d\)/);
  });
});

describe("tierFormBlockedReason — why Save is grey", () => {
  it("is null for an untouched draft", () => {
    expect(tierFormBlockedReason(base(), base())).toBeNull();
  });

  it("is null for a valid edit", () => {
    expect(tierFormBlockedReason({ ...base(), quotaBytes: "10" }, base())).toBeNull();
  });

  it("names the field and the rule when a required count is blanked", () => {
    const reason = tierFormBlockedReason({ ...base(), rateCapacity: "" }, base());
    expect(reason).toBe("Burst must be a whole number of 1 or more.");
  });

  it("catches a value that only LOOKS numeric", () => {
    // "1,000" is what an operator types when they are thinking in thousands; Number() gives NaN,
    // and without a stated reason a grey Save beside a field reading 1,000 reads as a broken form.
    const reason = tierFormBlockedReason({ ...base(), quotaTokens: "1,000" }, base());
    expect(reason).toMatch(/Tokens must be a whole number/);
  });

  // The gate checks only the CHANGED fields. A row that arrived from the backend holding a value
  // this form would reject is not the operator's to answer for — blocking on it would make the row
  // permanently unsavable, including the edit that would have fixed it.
  it("does not block on an untouched field that the stored row already violates", () => {
    const stored: TierDraft = { ...base(), rateCapacity: "0" };
    const form: TierDraft = { ...stored, quotaBytes: "10" };
    expect(tierFormBlockedReason(form, stored)).toBeNull();
    expect(bodyFrom(tierChanges(form, stored))).toEqual({ quotaBytes: 10 });
  });
});
