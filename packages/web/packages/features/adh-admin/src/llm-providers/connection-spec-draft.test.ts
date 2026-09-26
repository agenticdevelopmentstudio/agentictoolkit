import { describe, expect, it } from "vitest";
import {
  connectionSpecFromDraft,
  draftFromConnectionSpec,
  emptyConnectionSpecDraft,
  validateConnectionSpecDraft,
} from "./connection-spec-draft";

describe("connection-spec-draft: headerVars", () => {
  it("round-trips headerVars through draft <-> spec without dropping them", () => {
    // The regression this guards: before headerVars support, loading then saving a
    // template that declared headerVars (e.g. a seeded Portkey row) silently stripped
    // them, because draftFromConnectionSpec ignored the field and connectionSpecFromDraft
    // never re-emitted it.
    const spec = {
      specVersion: 1 as const,
      auth: { type: "header" as const, header: "x-portkey-api-key", scheme: "raw" as const },
      headerVars: [
        { header: "x-portkey-provider", label: "Upstream provider", example: "openai" },
      ],
    };
    const draft = draftFromConnectionSpec(spec);
    expect(draft.headerVars).toEqual([
      { localId: expect.any(String), header: "x-portkey-provider", label: "Upstream provider", example: "openai", secret: false },
    ]);
    const back = connectionSpecFromDraft(draft);
    expect(back?.headerVars).toEqual([
      { header: "x-portkey-provider", label: "Upstream provider", example: "openai" },
    ]);
  });

  it("drops header vars with a blank name and omits the key when there are none", () => {
    const draft = emptyConnectionSpecDraft();
    draft.headerVars = [
      { localId: "a", header: "  ", label: "", example: "", secret: false },
    ];
    // A single blank-named row is nothing to configure → null spec.
    expect(connectionSpecFromDraft(draft)).toBeNull();
  });

  it("rejects a reserved or malformed header-var name", () => {
    const reserved = emptyConnectionSpecDraft();
    reserved.headerVars = [{ localId: "a", header: "Authorization", label: "", example: "", secret: false }];
    expect(validateConnectionSpecDraft(reserved)).toMatch(/invalid or reserved/);

    const dup = emptyConnectionSpecDraft();
    dup.headerVars = [
      { localId: "a", header: "x-key", label: "", example: "", secret: false },
      { localId: "b", header: "X-Key", label: "", example: "", secret: false },
    ];
    expect(validateConnectionSpecDraft(dup)).toMatch(/Duplicate header variable/);
  });

  it("marks a header var secret when the flag is set", () => {
    const draft = emptyConnectionSpecDraft();
    draft.headerVars = [
      { localId: "a", header: "x-vk", label: "Virtual key", example: "vk-123", secret: true },
    ];
    expect(connectionSpecFromDraft(draft)?.headerVars).toEqual([
      { header: "x-vk", label: "Virtual key", example: "vk-123", secret: true },
    ]);
  });
});
