"use client";

import type { ReactElement } from "react";
import { PreferencesCard } from "./PreferencesCard";
import { ContactsCard } from "./ContactsCard";

/**
 * The bespoke /notifications account workspace: notification preferences +
 * contact-method management (verify email/phone). Replaces the generic
 * settings.notifications CRUD table (feature-routes.ts marks it `custom`).
 *
 * No title, help or API button of its own: the settings registry's FeatureTitle draws all three
 * above every topic, and this panel used to repeat them — centred, at a narrower width than its
 * siblings — so it read as a page from another site. PreferencesCard owns the panel's frame (its
 * Cancel/Save bar sits above the scrolling body), and the contacts list rides inside that body,
 * under its own "Contact methods" section heading.
 */
export function NotificationsWorkspace(): ReactElement {
  return (
    <PreferencesCard>
      <ContactsCard />
    </PreferencesCard>
  );
}
