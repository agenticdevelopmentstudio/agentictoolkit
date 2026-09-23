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
