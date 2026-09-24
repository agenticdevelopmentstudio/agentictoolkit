"use client";

import { useMemo, useState, type ReactElement, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Switch } from "@agenticdevelopertoolkit/ui/components/switch";
import {
  EditableList,
  useEditableList,
  type EditableListColumn,
} from "@agenticdevelopertoolkit/ui/blocks";
// No RecordApiButton here: the settings registry's FeatureTitle carries the topic's API link
// (`/notifications/preferences`) above every panel, and a second one inside it was a duplicate.
import {
  DetailSection,
  EditActionBar,
  SettingsBody,
  useReportSettingsDirty,
} from "@agentic-toolkit/resource";
import {
  listPreferences,
  savePreferences,
  type NotificationPref,
  type NotificationPrefInput,
} from "../api/account";

// Human labels for the backend categories (must cover lib/notificationCategories.ts —
// an unmapped category falls back to rendering its raw enum string as the title, so a category
// added there and forgotten here reads as `project_due` on the settings page rather than
// failing anywhere a build would catch).
const CATEGORY_LABELS: Record<string, { title: string; blurb: string }> = {
  account: {
    title: "Account & security",
    blurb: "Sign-in alerts, password changes, and verification codes.",
  },
  community_reply: {
    title: "Replies",
    blurb: "When someone replies to a thread you started.",
  },
  community_mention: {
    title: "Mentions",
    blurb: "When someone @-mentions you in the community.",
  },
  admin_announcement: {
    title: "Announcements",
    blurb: "Product news and announcements from the team.",
  },
  direct_message: {
    title: "Direct messages",
    blurb: "When someone sends you a direct message.",
  },
  project_assigned: {
    title: "Work assigned to you",
    blurb: "When someone puts a work item in your hands.",
  },
  project_mention: {
    title: "Project mentions",
    blurb: "When someone @-mentions you on a work item.",
  },
  project_comment: {
    title: "Work item comments",
    blurb: "When someone comments on an item you filed or hold.",
  },
  project_status: {
    title: "Work item status",
    blurb: "When an item you filed or hold moves to a new column.",
  },
  project_due: {
    title: "Due dates",
    blurb: "When an item you filed or hold is due today, or has gone overdue.",
  },
};

type Channel = "email" | "sms";
type Override = Partial<Record<Channel, boolean>>;

/** One row of the preferences table: the served preference plus its human label, looked up once. */
type PrefRow = NotificationPref & { title: string; blurb: string };

export interface PreferencesCardProps {
  /** Rendered in the panel body BELOW the preferences table (Notifications puts its contact
   *  methods here). A slot rather than a sibling because this card owns the top-of-panel
   *  Cancel/Save bar: the bar has to sit above the scrolling body, so the body is this card's
   *  too, and anything else the panel shows has to be inside it. */
  children?: ReactNode;
}

export function PreferencesCard({ children }: PreferencesCardProps = {}): ReactElement {
  const qc = useQueryClient();
  const { data, isLoading, error } = useQuery({
    queryKey: ["account", "preferences"],
    queryFn: listPreferences,
  });
  // User edits live here; the displayed value is override ?? server value, so we
  // never sync server data into state with an effect.
  const [overrides, setOverrides] = useState<Record<string, Override>>({});

  const save = useMutation({
    mutationFn: (prefs: NotificationPrefInput[]) => savePreferences(prefs),
    onSuccess: (prefs) => {
      qc.setQueryData(["account", "preferences"], prefs);
      setOverrides({});
    },
  });

  function valueOf(p: NotificationPref, ch: Channel): boolean {
    return overrides[p.category]?.[ch] ?? p[ch];
  }
  function toggle(category: string, ch: Channel, next: boolean) {
    // Clear the prior save's outcome on any edit, so the "Saved" note can't reappear when a
    // toggle is flipped back to its saved value, and a stale failure doesn't sit beside new edits.
    if (save.isSuccess || save.isError) save.reset();
    setOverrides((prev) => ({ ...prev, [category]: { ...prev[category], [ch]: next } }));
  }

  // A real diff of the displayed value against the loaded row, so a toggle flipped and flipped
  // back reports clean. `undefined` while the query is in flight — nothing is loaded, so nothing
  // can be unsaved.
  const dirty = data?.some((p) => valueOf(p, "email") !== p.email || valueOf(p, "sms") !== p.sms);

  // NotificationsWorkspace renders this card bare — there is no enclosing form whose dirty state
  // covers these toggles, so without this report every exit silently drops them.
  useReportSettingsDirty("notification-preferences", dirty === true);

  function onSave() {
    if (!data) return;
    // The loaded row, with the two fields this card edits replaced — not a literal rebuilt from
    // the fields it happens to know about. A save has to carry every field the request requires,
    // and this card owns exactly two of them; the rest ride along at the values they were served
    // at, which is what "I did not touch that" means over a whole-row PUT. Spelling them out
    // instead made the arrival of `inApp` a compile error here, in a card that has no opinion
    // about in-app delivery and no honest value to supply for it.
    save.mutate(
      data.map((p) => ({ ...p, email: valueOf(p, "email"), sms: valueOf(p, "sms") })),
    );
  }

  /** Cancel drops every unsaved toggle — the grid goes back to what the server served. */
  function onCancel() {
    if (save.isSuccess || save.isError) save.reset();
    setOverrides({});
  }

  const rows: PrefRow[] | undefined = useMemo(
    () =>
      data?.map((p) => ({
        ...p,
        ...(CATEGORY_LABELS[p.category] ?? { title: p.category, blurb: "" }),
      })),
    [data],
  );

  // One row per notification kind, one Switch column per channel — the same table admin draws,
  // not a bespoke grid. A channel toggle means nothing across a selection, so the table is not
  // selectable and carries no bar verbs: Cancel/Save on the EditActionBar commit the whole grid.
  const channelColumn = (ch: Channel, header: string, spoken: string): EditableListColumn<PrefRow> => ({
    key: ch,
    header,
    width: "5rem",
    resizable: false,
    sortable: false,
    searchable: false,
    render: (p) => (
      <Switch
        aria-label={`${p.title} ${spoken}`}
        checked={valueOf(p, ch)}
        onCheckedChange={(v) => toggle(p.category, ch, v)}
        // Frozen while a save is in flight: the save's success clears EVERY override, so a flip
        // made now — not in the request being saved — would be shown and then silently undone.
        disabled={save.isPending}
      />
    ),
  });
  const columns: EditableListColumn<PrefRow>[] = [
    {
      key: "category",
      header: "Notification",
      value: (p) => p.title,
      render: (p) => (
        <span className="flex min-w-0 flex-col">
          <span className="truncate text-sm font-medium text-apt-text">{p.title}</span>
          {p.blurb && <span className="truncate text-xs text-apt-text-muted">{p.blurb}</span>}
        </span>
      ),
    },
    channelColumn("email", "Email", "email"),
    channelColumn("sms", "SMS", "SMS"),
  ];

  const list = useEditableList<PrefRow>({
    rows: isLoading ? undefined : rows,
    getRowId: (p) => p.category,
    columns,
  });

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      {/* At the top of the panel, like every other single-record settings form: the grid is ONE
          record (a whole-row PUT), so it gets the one Cancel/Save strip, not an inline button
          at the bottom of a list that can scroll it out of sight. */}
      <EditActionBar
        dirty={dirty === true}
        canSave={dirty === true}
        saving={save.isPending}
        onCancel={onCancel}
        onSave={onSave}
        status={
          save.isError ? (
            <span className="text-apt-error">Couldn’t save — try again.</span>
          ) : save.isSuccess && !dirty ? (
            <span className="text-apt-text-muted">Saved.</span>
          ) : null
        }
      />
      <SettingsBody width="full">
        <DetailSection title="Preferences">
          <p className="text-sm text-apt-text-muted">
            Choose how you hear from us. SMS needs a verified phone number.
          </p>
          <EditableList
            list={list}
            ariaLabel="Notification preferences"
            selectable={false}
            loading={isLoading}
            error={error}
            errorTitle="Couldn’t load your preferences"
            columnWidthsKey="settings-notification-preferences"
            searchPlaceholder="Notification"
            emptyLabel="No notification categories."
            emptyFilteredLabel="No notifications match this search."
          />
        </DetailSection>
        {children}
      </SettingsBody>
    </div>
  );
}
