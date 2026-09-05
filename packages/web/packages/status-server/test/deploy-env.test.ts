import { describe, it, expect } from "vitest";
import { deployEnv, envFromBranch } from "../src/monitor/deploy-view";
import { providerDeployToDTO, type ProviderDeploy } from "../src/monitor/provider-deploy";

/**
 * WHICH TIER A DEPLOY BELONGS TO — and why the BRANCH is the only signal that answers it
 * without being able to lie.
 *
 * Three signals are available on a deploy row and two of them are fallible:
 *
 *  - `environment` (the provider's promotion target) is fallible by CONSTRUCTION. Every
 *    Vercel project has its own production target, so `hub-help-testing`'s target is
 *    literally "production". It can never distinguish our tiers, for any project.
 *  - the PROJECT NAME is fallible by CONVENTION. `envFromProject` reads a `-testing` /
 *    `-staging` suffix (or a legacy `testing.` / `staging.` prefix) and calls everything
 *    else production — so a testing project whose name carries no suffix reads PROD, and
 *    the default is the most dangerous of the three tiers to be wrong about.
 *  - the BRANCH is the deploy pipeline's own input. `prepared` builds testing, `staging`
 *    builds staging, `production` builds production; that mapping IS the deployment
 *    process, not a naming habit layered over it.
 *
 * So the branch decides whenever it can, and the older name/target rule survives only as
 * the fallback for a row that has no branch (a pre-existing row, or a platform that did
 * not report one) or a branch outside the map (a hand-triggered build off some other ref).
 */

describe("envFromBranch — the deployment process, as a table", () => {
  it("maps the three deploying branches to the tiers they build", () => {
    expect(envFromBranch("prepared")).toBe("testing");
    expect(envFromBranch("staging")).toBe("staging");
    expect(envFromBranch("production")).toBe("production");
  });

  it("answers null for anything it was not told about, rather than guessing", () => {
    // Null is what hands the decision back to the name/target fallback. Returning
    // "production" here — `envFromProject`'s default — would be the same fallible guess
    // this function exists to replace, and `main` is precisely the branch that would hit
    // it: it deploys nothing today, so no row should be badged from it.
    expect(envFromBranch("main")).toBeNull();
    expect(envFromBranch("feature/some-work")).toBeNull();
    expect(envFromBranch(null)).toBeNull();
    expect(envFromBranch("")).toBeNull();
  });

  it("answers null for a branch that names something on Object.prototype", () => {
    // A plain object literal indexed by an arbitrary string reaches the PROTOTYPE CHAIN:
    // `{}["toString"]` is a function, `{}["__proto__"]` is an object, and both are truthy
    // — so `?? null` never fires and the lookup returns a non-string that the
    // `Record<string, string>` annotation swears is a string. `deployEnv` would then hand
    // a function to a badge. These are legal git branch names, so the map has to be a
    // lookup over its OWN keys, not over everything it inherits.
    for (const branch of ["constructor", "toString", "valueOf", "hasOwnProperty", "__proto__"]) {
      expect(envFromBranch(branch)).toBeNull();
      expect(deployEnv("vercel", "hub-help-testing", "production", branch)).toBe("testing");
    }
  });
});

describe("deployEnv — branch first, then the old fallible signals", () => {
  it("reads the tier off the BRANCH even when the project name says nothing", () => {
    // The case the name rule cannot get right: a testing project with no `-testing`
    // suffix. `envFromProject("hub")` is "production", and before the branch rule that
    // is exactly what the badge said while the project served testing.
    expect(deployEnv("vercel", "hub", "production", "prepared")).toBe("testing");
    expect(deployEnv("vercel", "hub", "production", "staging")).toBe("staging");
  });

  it("lets the branch OVERRIDE a name that disagrees with it", () => {
    // A `-testing` project building the `production` branch is a misconfiguration, and
    // the branch is what says so. Deferring to the name here would hide it behind a badge
    // that looks right — the branch is authoritative precisely so this surfaces.
    expect(deployEnv("vercel", "hub-help-testing", "production", "production")).toBe("production");
  });

  it("falls back to the project name when there is no branch to read", () => {
    // Every row written before the branch column was populated, and every platform that
    // does not report one. This is the pre-existing rule, unchanged.
    expect(deployEnv("vercel", "hub-help-testing", "production", null)).toBe("testing");
    expect(deployEnv("vercel", "staging.adh", "production", null)).toBe("staging");
    expect(deployEnv("vercel", "hub", "production", null)).toBe("production");
  });

  it("falls back for a branch outside the map", () => {
    // A hand-triggered build off some other ref still has to be labelled something, and
    // the name is the better of the two remaining guesses.
    expect(deployEnv("vercel", "hub-help-testing", "production", "main")).toBe("testing");
  });

  it("still trusts a non-Vercel platform's reported environment when no branch decides", () => {
    // Railway and Cloudflare report a REAL environment name, so the stored value stands —
    // a Railway testing build must not be collapsed to PROD by a name with no suffix.
    expect(deployEnv("railway", "adh-backend", "testing", null)).toBe("testing");
    expect(deployEnv("cloudflare-pages", "temporal-web", "", null)).toBe("production");
  });

  it("but the branch outranks a non-Vercel stored environment too", () => {
    // The rule is about which signal can lie, not about which platform reported it. A
    // Railway environment NAMED "production" that builds `prepared` is serving testing.
    expect(deployEnv("railway", "adh-backend", "production", "prepared")).toBe("testing");
  });
});

/**
 * THE DTO CARRIES THE TIER, so no client has to re-derive it.
 *
 * The Deployments panel rendered `environment` straight — Vercel's promotion target, which
 * is "production" for every project — so it badged the whole testing fleet PROD on a screen
 * next to an activity list that had just been taught otherwise. The client cannot fix that
 * itself without a second copy of `deployEnv`, which is the duplicate that caused the
 * original divergence, so the derivation stays here and rides down on the wire.
 */
describe("providerDeployToDTO stamps the tier", () => {
  function deploy(over: Partial<ProviderDeploy> = {}): ProviderDeploy {
    return {
      id: "d1", platform: "vercel", projectName: "hub-help-testing", providerProjectId: null,
      buildPhase: "failed", deployPhase: "none", environment: "production",
      commitHash: null, commitMessage: null, branch: null, commitRepo: null, url: null,
      createdAt: new Date(1000), ...over,
    };
  }

  it("derives it from the branch, alongside the RAW promotion target", () => {
    const dto = providerDeployToDTO(deploy({ projectName: "hub", branch: "prepared" }), null);
    expect(dto.tier).toBe("testing");
    // `environment` stays raw: the preview gate, `boardTargetKey` and the SQL grouping all
    // read it, and "testing" cannot be read back into Vercel's target.
    expect(dto.environment).toBe("production");
  });

  it("falls back to the name rule when the row has no branch", () => {
    expect(providerDeployToDTO(deploy(), null).tier).toBe("testing");
    expect(providerDeployToDTO(deploy({ projectName: "hub" }), null).tier).toBe("production");
  });

  it("is NULL for a Vercel preview, which is not a deployment of any tier", () => {
    // A preview reports no environment. Its branch is a feature ref and its project name is
    // the production project's, so both fallbacks would badge it — `deployEnv` has no
    // "don't know" to return, and the honest answer is to say nothing at all. This is the
    // same gate `ownedDeployTarget` applies before a preview can become a Problem.
    expect(providerDeployToDTO(deploy({ environment: null, branch: "feature/x" }), null).tier).toBeNull();
    expect(providerDeployToDTO(deploy({ environment: "" }), null).tier).toBeNull();
  });
});
