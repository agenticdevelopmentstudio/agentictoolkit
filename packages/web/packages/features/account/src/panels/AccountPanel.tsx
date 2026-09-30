"use client";

import { useState } from "react";
import Link from "next/link";

// The base hook, not hub's `useAuth` wrapper (which only adds `tenantId`) — this
// panel reads nothing but `user.email`, so the base `AuthUser` is behaviour-identical.
import { useAuth } from "@agentic-toolkit/auth";
import { changePassword } from "../api/auth";
import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";
import { DetailsPane, type DetailsSection } from "@agentic-toolkit/resource";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { DetailSection } from "@agentic-toolkit/resource";
import { useSettingsNav } from "../layout/settings-nav";

const MIN_PASSWORD_LENGTH = 8;

/**
 * Account: change password. Email management is handled by the Notifications
 * contacts workspace — see the link below.
 */
export function AccountPanel() {
  const { user } = useAuth();
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const [confirm, setConfirm] = useState("");
  const goToTopic = useSettingsNav()?.goToTopic;

  const pwFilled = Boolean(current || next || confirm);
  const dirty = pwFilled;

  const pwError = pwFilled
    ? next.length < MIN_PASSWORD_LENGTH
      ? `New password must be at least ${MIN_PASSWORD_LENGTH} characters.`
      : next !== confirm
        ? "New password and confirmation don't match."
        : !current
          ? "Enter your current password."
          : null
    : null;

  function handleCancel() {
    setCurrent("");
    setNext("");
    setConfirm("");
  }

  // The password change is the pane's one section: the pane's bar saves it, reports it dirty to
  // the settings rail, and shows the saving / saved / error line.
  const section: DetailsSection = {
    dirty,
    canSave: !pwError,
    blockedReason: pwError,
    save: async () => {
      try {
        await changePassword({ currentPassword: current, newPassword: next });
      } catch (err) {
        reportUnexpectedAuthError(err, { feature: "account-panel", step: "save" });
        throw err instanceof Error ? err : new Error("Could not save.");
      }
      handleCancel();
    },
    reset: handleCancel,
  };

  if (!user) return null;

  return (
    // The settings rail's own header carries the title, the API button and the help, so this bar
    // is just Save / Cancel, in place.
    <DetailsPane section={section} hoist={false} showApi={false} bodyClassName="px-6 py-6">
      <div className="flex min-w-0 max-w-3xl flex-col gap-8">
        <DetailSection title="Email">
          <Card>
            <CardContent className="flex flex-col gap-2">
              <p className="text-sm text-apt-text-muted">
                Current:{" "}
                <span className="text-apt-text">{user.email}</span>
              </p>
              <p className="text-xs text-apt-text-muted">
                To add or change email addresses, go to{" "}
                {/* The ACCOUNT's Notifications section, where the email addresses this
                    paragraph is about are edited — a SIBLING of this panel in the same
                    rail, not a route.

                    Twice a URL, twice wrong. `/<slug>/notifications` was a workspace
                    feature path no feature ever claimed and it 404'd on hub; changing it to
                    `/settings/notifications` fixed hub and broke the other 44 sites, where
                    no `app/settings/` directory exists at all — and there the 404 costs the
                    user the modal AND the page it was layered over. There is no href that
                    is right on every host, because on most of them the section has no URL.

                    So ask the host to switch sections instead (settings-nav.tsx).
                    `goToTopic` is null only where the panel is rendered outside a
                    SettingsLayout rail — hub's workspace-settings stack, which is hub-only,
                    and where /settings/notifications does resolve. */}
                {goToTopic ? (
                  <button
                    type="button"
                    onClick={() => goToTopic("notifications")}
                    className="text-apt-text underline hover:text-apt-text-muted"
                  >
                    Notifications
                  </button>
                ) : (
                  <Link
                    href="/settings/notifications"
                    className="text-apt-text underline hover:text-apt-text-muted"
                  >
                    Notifications
                  </Link>
                )}
                .
              </p>
            </CardContent>
          </Card>
        </DetailSection>

        <DetailSection title="Password">
          <Card>
            <CardContent className="flex flex-col gap-4">
              <div className="flex flex-col gap-2">
                <Label htmlFor="account-current-password">Current password</Label>
                <Input
                  id="account-current-password"
                  type="password"
                  value={current}
                  onChange={(e) => setCurrent(e.target.value)}
                  autoComplete="current-password"
                />
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="account-new-password">New password</Label>
                <Input
                  id="account-new-password"
                  type="password"
                  value={next}
                  onChange={(e) => setNext(e.target.value)}
                  autoComplete="new-password"
                />
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="account-confirm-password">Confirm new password</Label>
                <Input
                  id="account-confirm-password"
                  type="password"
                  value={confirm}
                  onChange={(e) => setConfirm(e.target.value)}
                  autoComplete="new-password"
                />
              </div>
              <ErrorText error={pwError} className="text-xs" />
            </CardContent>
          </Card>
        </DetailSection>
      </div>
    </DetailsPane>
  );
}
