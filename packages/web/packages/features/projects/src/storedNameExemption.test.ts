// The four name-unique validators fold case; the backend's unique indexes do not. So "Sprint 12"
// and "sprint 12" can both exist, and before the stored-name exemption each one's Save was
// disabled for EVERY edit — a date change, a description — because its own name "collided" with
// the other. These pin both halves: an untouched name passes, a TYPED collision is still refused.
import { describe, it, expect } from "vitest";
import { iterationBlank, iterationValidate } from "./IterationDetail";
import { milestoneBlank, milestoneValidate } from "./MilestoneDetail";
import { programBlank, programValidate } from "./ProgramDetail";
import { templateBlank, templateValidate } from "./TemplateDetail";

const iteration = { ...iterationBlank(), name: "Sprint 12", startDate: "2026-01-01", endDate: "2026-01-14" };
const milestone = { ...milestoneBlank(), name: "Sprint 12" };
const program = { ...programBlank(), name: "Sprint 12" };
const template = { ...templateBlank(), kind: "project" as const, name: "Sprint 12" };

describe("name uniqueness exempts the stored name", () => {
  it("iteration", () => {
    expect(iterationValidate(iteration, ["sprint 12"], "Sprint 12")).toBeNull();
    expect(iterationValidate(iteration, ["sprint 12"], "Sprint 11")).toMatch(/already exists/);
    expect(iterationValidate(iteration, ["sprint 12"])).toMatch(/already exists/);
  });
  it("milestone", () => {
    expect(milestoneValidate(milestone, ["sprint 12"], "Sprint 12")).toBeNull();
    expect(milestoneValidate(milestone, ["sprint 12"], "Sprint 11")).toMatch(/already exists/);
  });
  it("program", () => {
    expect(programValidate(program, ["sprint 12"], "Sprint 12")).toBeNull();
    expect(programValidate(program, ["sprint 12"], "Sprint 11")).toMatch(/already exists/);
  });
  it("template", () => {
    const taken = [{ name: "sprint 12", kind: "project" as const }];
    expect(templateValidate(template, taken, "Sprint 12")).toBeNull();
    expect(templateValidate(template, taken, "Sprint 11")).toMatch(/already exists/);
  });
});

// All four decide "kept the name" through the shared `unchangedFromStored`, so they cannot drift
// apart on it again: the stored name is compared trimmed and case-sensitively, and a create —
// where useMasterDetailForm hands over no stored record — is always checked.
describe("the four agree on what counts as keeping the stored name", () => {
  const cases: [string, (storedName?: string) => string | null][] = [
    ["iteration", (s) => iterationValidate(iteration, ["sprint 12"], s)],
    ["milestone", (s) => milestoneValidate(milestone, ["sprint 12"], s)],
    ["program", (s) => programValidate(program, ["sprint 12"], s)],
    ["template", (s) => templateValidate(template, [{ name: "sprint 12", kind: "project" }], s)],
  ];
  it.each(cases)("%s: a create (no stored name) is still checked", (_, validate) => {
    expect(validate(undefined)).toMatch(/already exists/);
  });
  it.each(cases)("%s: the stored name is compared trimmed", (_, validate) => {
    expect(validate("  Sprint 12 ")).toBeNull();
  });
  it.each(cases)("%s: re-casing the stored name is an edit, and is checked", (_, validate) => {
    expect(validate("SPRINT 12")).toMatch(/already exists/);
  });
});
