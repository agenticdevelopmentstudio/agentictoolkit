"use client";

import { useEffect, useState } from "react";
import Link from "next/link";

// The base hook, not hub's `useAuth` wrapper (which only adds `tenantId`) — this
// panel reads nothing but `user.email`, so the base `AuthUser` is behaviour-identical.
import { useAuth } from "@agentic-toolkit/auth";
import { changePassword } from "../api/auth";
import { reportUnexpectedAuthError } from "@agentic-toolkit/auth";
import { useSettingsDirty, SettingsBody } from "@agentic-toolkit/resource";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { EditActionBar } from "@agentic-toolkit/resource";
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
  const [saving, setSaving] = useState(false);
  const [status, setStatus] = useState<{ ok: boolean; msg: string } | null>(null);
  const { reportDirty } = useSettingsDirty();
  const goToTopic = useSettingsNav()?.goToTopic;

  const pwFilled = Boolean(current || next || confirm);
  const dirty = pwFilled;
  useEffect(() => {
    reportDirty("account", dirty);
    return () => reportDirty("account", false);
  }, [dirty, reportDirty]);

  if (!user) return null;

  const pwError = pwFilled
    ? next.length < MIN_PASSWORD_LENGTH
      ? `New password must be at least ${MIN_PASSWORD_LENGTH} characters.`
      : next !== confirm
        ? "New password and confirmation don't match."
        : !current
          ? "Enter your current password."
          : null
    : null;

  const canSave = dirty && !pwError;

  async function handleSave() {
    if (!canSave) return;
    setStatus(null);
    setSaving(true);
    try {
      await changePassword({ currentPassword: current, newPassword: next });
      setCurrent("");
      setNext("");
      setConfirm("");
      setStatus({ ok: true, msg: "Password updated." });
    } catch (err) {
      reportUnexpectedAuthError(err, { feature: "account-panel", step: "save" });
      setStatus({ ok: false, msg: err instanceof Error ? err.message : "Could not save." });
    } finally {
      setSaving(false);
    }
  }

  function handleCancel() {
    setCurrent("");
    setNext("");
    setConfirm("");
    setStatus(null);
  }

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <EditActionBar
        dirty={dirty}
        canSave={canSave}
        saving={saving}
        onCancel={handleCancel}
        onSave={handleSave}
        status={
          status ? (
            <span className={status.ok ? "text-apt-green" : "text-apt-red"}>{status.msg}</span>
          ) : null
        }
      />
      <SettingsBody>
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
                  onChange={(e) => {
                    setCurrent(e.target.value);
                    setStatus(null);
                  }}
                  autoComplete="current-password"
                />
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="account-new-password">New password</Label>
                <Input
                  id="account-new-password"
                  type="password"
                  value={next}
                  onChange={(e) => {
                    setNext(e.target.value);
                    setStatus(null);
                  }}
                  autoComplete="new-password"
                />
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="account-confirm-password">Confirm new password</Label>
                <Input
                  id="account-confirm-password"
                  type="password"
                  value={confirm}
                  onChange={(e) => {
                    setConfirm(e.target.value);
                    setStatus(null);
                  }}
                  autoComplete="new-password"
                />
              </div>
              <ErrorText error={pwError} className="text-xs" />
            </CardContent>
          </Card>
        </DetailSection>
      </SettingsBody>
    </div>
  );
}
