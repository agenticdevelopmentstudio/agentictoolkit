"use client";

import dynamic from "next/dynamic";
import { type ReactElement, type ReactNode } from "react";

import { type AppearancePrefs } from "@agenticdevelopertoolkit/themes";
// The PACKAGE PATH, not '../auth/useAppearanceSettings'. `src/auth/index.ts` is its own tsup
// entry and `@agentic-toolkit/adh/auth` is `external`, so a relative import would inline a
// SECOND copy of this hook (and its transitive `@agentic-toolkit/adh/telemetry/report-error`
// hop) into dist/settings/UserSettingsOverlay.js — which is what it did: three occurrences of
// `useAppearanceSettings` in dist/auth/index.js AND three more in the overlay chunk. The
// duplicate is only weight today, but every relative hop across an entry boundary in this
// package is one refactor away from being the forked-state bug tsup.config.ts documents at
// length — the hook's own file carries the same rule for the same reason.
import { useAppearanceSettings } from "@agentic-toolkit/adh/auth";
import {
  ToggleGroup,
  ToggleGroupItem,
} from "@agenticdevelopertoolkit/ui/components/toggle-group";
import { Checkbox } from "@agenticdevelopertoolkit/ui/components/checkbox";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";

import { SettingRow } from "@agentic-toolkit/account";
import { DetailSection, SettingsBody } from "@agentic-toolkit/resource";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";

/**
 * Appearance: accessibility preferences, plus a dev-only theme picker. Each control writes
 * straight through (no Save bar — changes apply to the document live) and is saved against
 * the USER, so the choice made here follows them to every other site in the family.
 *
 * There is no light/dark/system control. The family ships ONE presentation, and its theme
 * (DEFAULT_SITE_THEME in @agentic-toolkit/adh) is dark whatever the device says — a picker
 * offering "Light" would set a preference the theme's own palette overrides, which is
 * worse than not offering it.
 *
 * The `colorMode` preference itself is NOT retired and a stored value is NOT inert:
 * appearance.ts:133-135 still writes `data-color-mode` on every apply and still toggles
 * the `.dark` class from it, so a value left behind by the old control keeps selecting
 * which half of a theme's stylesheet matches. What makes that invisible on the default
 * theme is the theme, not the plumbing — a DARK-ALWAYS theme gives its light-mode
 * selectors the dark palette on purpose, so both branches land on the same colours. Any
 * theme that does vary by mode still follows the stored value, which is why nothing here
 * deletes it.
 *
 * That is a load-bearing property of the default theme, not a happy accident of which one
 * it is: this comment used to name `fishlamp` for it, and went stale the moment the
 * default moved to a `charcoal` that still shipped a real light block — from then until
 * this was fixed, a light-OS visitor got a light site and this panel offered nothing to
 * undo it. fullPaletteThemes.test.ts now asserts dark-always of DEFAULT_SITE_THEME itself,
 * so the sentence above cannot go quietly stale again.
 *
 * The theme row that replaced the control is a real theme picker — every theme the site
 * emits — and it is DEV-ONLY, twice over: it is loaded through a build-gated
 * `next/dynamic` (see ThemePickerRow below, and the chunk-gate contract in
 * adh-registry/src/deployment-env.ts), and the `<style>` blocks it switches between are
 * emitted by AdhThemeStyle only in the dev deployment envs, so in production there is
 * nothing to list even if the gate were wrong.
 */

interface Option<T extends string> {
  value: T;
  label: string;
  icon?: ReactNode;
}

const REDUCE_MOTION_OPTIONS: Option<AppearancePrefs["reduceMotion"]>[] = [
  { value: "auto", label: "Default" },
  { value: "on", label: "On" },
  { value: "off", label: "Off" },
];

const CONTRAST_OPTIONS: Option<AppearancePrefs["contrast"]>[] = [
  { value: "default", label: "Default" },
  { value: "high", label: "High" },
  { value: "extra-high", label: "Extra High" },
];

const TEXT_SIZE_OPTIONS: Option<AppearancePrefs["textSize"]>[] = [
  { value: "default", label: "Default" },
  { value: "small", label: "Small" },
  { value: "large", label: "Large" },
  { value: "extra-large", label: "Extra Large" },
];

const SPACING_OPTIONS: Option<AppearancePrefs["spacing"]>[] = [
  { value: "compact", label: "Compact" },
  { value: "comfortable", label: "Comfortable" },
  { value: "spacious", label: "Spacious" },
];

/** A labelled segmented control. `iconsOnly` shows the icon with the label moved
 *  to an accessible name + tooltip. */
function SegmentedRow<T extends string>({
  label,
  description,
  value,
  options,
  onChange,
  iconsOnly,
}: {
  label: string;
  description?: string;
  value: T;
  options: Option<T>[];
  onChange: (value: T) => void;
  iconsOnly?: boolean;
}) {
  return (
    <SettingRow label={label} description={description}>
      <ToggleGroup
        aria-label={label}
        value={[value]}
        onValueChange={(next: string[]) => {
          const v = next[0];
          // Single-select: ignore the empty array from clicking the active item.
          if (v) onChange(v as T);
        }}
      >
        {options.map((o) => (
          <ToggleGroupItem
            key={o.value}
            value={o.value}
            aria-label={iconsOnly ? o.label : undefined}
            title={iconsOnly ? o.label : undefined}
          >
            {o.icon}
            {!iconsOnly && o.label}
          </ToggleGroupItem>
        ))}
      </ToggleGroup>
    </SettingRow>
  );
}

/** A labelled checkbox toggle. */
function CheckboxRow({
  id,
  label,
  description,
  checked,
  onCheckedChange,
}: {
  id: string;
  label: string;
  description?: string;
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
}) {
  return (
    <div className="flex items-start gap-3">
      <Checkbox
        id={id}
        checked={checked}
        onCheckedChange={onCheckedChange}
        className="mt-0.5"
      />
      <div className="min-w-0">
        <Label htmlFor={id} className="cursor-pointer">
          {label}
        </Label>
        {description && (
          <p className="mt-0.5 text-xs text-apt-text-muted">{description}</p>
        )}
      </div>
    </div>
  );
}

/**
 * The dev-only theme picker's chunk gate. The comparisons are written out INLINE so
 * webpack folds them while parsing and never registers the import — reading the
 * equivalent `DEV_BUILD` boolean instead leaves an identifier it will not fold past, so
 * the picker and `@agentic-toolkit/adh/themes/theme-preview` shipped to every production
 * site. The full contract is in adh-registry/src/deployment-env.ts.
 *
 * The production arm renders nothing rather than rejecting: unlike a lazily opened debug
 * surface, this row is on a page real users load, and "no theme picker" is the correct
 * production appearance, not an error.
 *
 * The import is the PACKAGE PATH, not `./ThemePickerRow`: this file now lives inside the
 * adh package itself, which builds with tsup's `bundle: true, splitting: false` — a
 * relative dynamic import would be inlined into THIS entry behind a lazy-init wrapper
 * rather than code-split, leaving the folded gate above with nothing left to gate.
 * ThemePickerRow has its own tsup entry and `external` pairing for exactly this reason —
 * see tsup.config.ts and the debug-env/SiteThemeConsole entry it mirrors.
 */
const ThemePickerRow =
  process.env.NEXT_PUBLIC_DEPLOYMENT_ENV === "local" ||
  process.env.NEXT_PUBLIC_DEPLOYMENT_ENV === "testing" ||
  process.env.NEXT_PUBLIC_DEPLOYMENT_ENV === "staging"
    ? dynamic(() => import("@agentic-toolkit/adh/settings/ThemePickerRow"), {
        ssr: false,
      })
    : (): null => null;

export function AppearancePanel(): ReactElement {
  const { prefs, set } = useAppearanceSettings();

  return (
    <SettingsBody>
      <p className="text-sm text-apt-text-muted">
        “Default” follows your device’s own setting where possible. These
        preferences are saved to your account, so they follow you to every site
        in the family.
      </p>

      {/* Sections in Cards, as Account and Profile draw them — rows floating on the page
          background looked like a different site's settings. */}
      <DetailSection title="Display">
        <Card>
          <CardContent className="flex flex-col gap-6">
            <ThemePickerRow />

            <SegmentedRow
              label="Reduce motion"
              description="Minimise animations and transitions."
              value={prefs.reduceMotion}
              options={REDUCE_MOTION_OPTIONS}
              onChange={(reduceMotion) => set({ reduceMotion })}
            />

            <SegmentedRow
              label="Contrast"
              description="Strengthen text and border contrast."
              value={prefs.contrast}
              options={CONTRAST_OPTIONS}
              onChange={(contrast) => set({ contrast })}
            />

            <SegmentedRow
              label="Text size"
              value={prefs.textSize}
              options={TEXT_SIZE_OPTIONS}
              onChange={(textSize) => set({ textSize })}
            />

            <SegmentedRow
              label="Spacing"
              description="Density of layout spacing."
              value={prefs.spacing}
              options={SPACING_OPTIONS}
              onChange={(spacing) => set({ spacing })}
            />
          </CardContent>
        </Card>
      </DetailSection>

      <DetailSection title="Accessibility">
        <Card>
          <CardContent className="flex flex-col gap-4">
            <CheckboxRow
              id="appearance-focus-outlines"
              label="Always show focus outlines"
              description="Show the focus ring even when navigating with a mouse."
              checked={prefs.focusOutlines}
              onCheckedChange={(focusOutlines) => set({ focusOutlines })}
            />
            <CheckboxRow
              id="appearance-underline-links"
              label="Always underline links"
              checked={prefs.underlineLinks}
              onCheckedChange={(underlineLinks) => set({ underlineLinks })}
            />
          </CardContent>
        </Card>
      </DetailSection>
    </SettingsBody>
  );
}
