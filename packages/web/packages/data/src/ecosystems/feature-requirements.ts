import type { CatalogFeature } from "./ecosystem-features";

/**
 * Feature requirements, pure — no React, no state. Part of the feature manager
 * (./feature-manager): what a feature brings in with it and what still needs it are the
 * manager's rules, read by every surface through it. `FeaturePickerDialog` uses them to
 * cascade a tick onto what it needs and to refuse a tick-off that would strand something
 * still on; `ManageFeaturesDialog` reuses {@link neededByMessage} to phrase the SAME copy
 * when the backend, not the picker, is the one that catches the race (another session
 * removed a dependency between the picker's confirm and the DELETE landing).
 */

/**
 * Every catalog key that must be on before `key` can be — `key`'s own `requiresFeatures`,
 * plus theirs, transitively. A cycle (the catalog should never have one, but this must not
 * hang if it does) terminates on the `seen` set rather than recursing forever.
 */
export function requiredClosure(key: string, catalog: readonly CatalogFeature[]): string[] {
  const byKey = new Map(catalog.map((f) => [f.key, f] as const));
  const seen = new Set<string>();
  const out: string[] = [];
  const visit = (k: string): void => {
    for (const dep of byKey.get(k)?.requiresFeatures ?? []) {
      if (seen.has(dep)) continue;
      seen.add(dep);
      out.push(dep);
      visit(dep);
    }
  };
  visit(key);
  return out;
}

/**
 * The catalog features — currently ON per `isOn` — that need `key`, directly or
 * transitively (their own {@link requiredClosure} includes it). A feature that is itself
 * off needs nothing: this is what makes turning `key` off safe once everything that once
 * needed it has already been turned off too.
 */
export function neededBy(
  key: string,
  catalog: readonly CatalogFeature[],
  isOn: (key: string) => boolean,
): CatalogFeature[] {
  return catalog.filter((f) => f.key !== key && isOn(f.key) && requiredClosure(f.key, catalog).includes(key));
}

/**
 * The feature the Manage features dialog lists for `key`: `key` itself, or — for a feature that
 * comes with another (`includedWith`) — the one it comes with, followed to the top. A chain that
 * loops (the catalog should never have one) stops where it would repeat.
 */
export function listedFeatureKey(key: string, catalog: readonly CatalogFeature[]): string {
  const byKey = new Map(catalog.map((f) => [f.key, f] as const));
  const seen = new Set<string>([key]);
  let at = key;
  for (let parent = byKey.get(at)?.includedWith; parent && !seen.has(parent); parent = byKey.get(at)?.includedWith) {
    seen.add(parent);
    at = parent;
  }
  return at;
}

/**
 * The catalog as the Manage features dialog lists it: without the features that come with
 * another (`includedWith`), each folded into the feature it comes with. What a folded feature
 * requires becomes its parent's requirement, named by the LISTED key — Client Auth needs Users and
 * User Authentication, so Applications, which brings Client Auth, needs Users. So the picker's
 * own cascade (tick Applications → Users ticks too) and its refusal (Users cannot go while
 * Applications is on) are the backend's rules, over the rows the owner can actually see.
 */
export function listedCatalog(catalog: readonly CatalogFeature[]): CatalogFeature[] {
  const listed = catalog.filter((f) => listedFeatureKey(f.key, catalog) === f.key);
  return listed.map((f) => {
    const requires = new Set<string>();
    for (const member of catalog) {
      if (listedFeatureKey(member.key, catalog) !== f.key) continue;
      for (const dep of member.requiresFeatures ?? []) {
        const listedDep = listedFeatureKey(dep, catalog);
        if (listedDep !== f.key) requires.add(listedDep);
      }
    }
    return requires.size === 0 && !f.requiresFeatures ? f : { ...f, requiresFeatures: [...requires] };
  });
}

/**
 * The picker's own copy for a blocked tick-off, given the blockers' labels — verbatim
 * "this feature is needed by ${labels.join(', ')} features". Shared with `ManageFeaturesDialog`
 * so the in-dialog refusal and the backend-race refusal read identically.
 */
export function neededByMessage(labels: readonly string[]): string {
  return `this feature is needed by ${labels.join(", ")} features`;
}
