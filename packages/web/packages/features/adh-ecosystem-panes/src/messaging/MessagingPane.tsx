"use client";

import { useCallback, useEffect, useState, type ReactElement, type ReactNode } from "react";
import { DetailHeaderActions, type TopicLeaf, useSettingsDirty } from "@agentic-toolkit/resource";
import { MessagingSurface, type SendMessageDraft } from "@agentic-toolkit/adh/messaging";
import {
  useMessagingStatus,
  useMessagingTemplates,
  useMessageLog,
  useSendMessage,
} from "../api/messaging";

/**
 * Per-product Messaging: send email/SMS to a customer of THIS ecosystem via its own
 * connected Postmark/Twilio integration, with a scoped message log. A channel is disabled
 * (banner) until the matching provider is connected on this product's Integrations tab.
 *
 * Everything a reader sees is `MessagingSurface`, which the platform-wide admin Messaging
 * tool renders too — this file is the ecosystem-scoped HALF: which endpoints the hooks
 * call, which words name the scope, and the settings-dirty registration. The two used to
 * be forked copies of one screen (docs/ui/fleet-ui-audit.md, Tier 6).
 */
export function MessagingPane({
  ecosystemId,
  help,
}: {
  ecosystemId?: string;
  /** Unused: the breadcrumb names the pane (kept for the ScopedPane prop shape). */
  title?: ReactNode;
  /** Contextual help for the feature, the "?" on the far right of the detail header. */
  help?: ReactNode;
  /** Unused: this pane has no deep-linkable sub-resource (kept for the ScopedPane prop shape). */
  leaf?: TopicLeaf;
}): ReactElement {
  const [page, setPage] = useState(1);
  const status = useMessagingStatus(ecosystemId);
  const { data: templates } = useMessagingTemplates();
  const log = useMessageLog(ecosystemId, page);
  const send = useSendMessage(ecosystemId);

  // Held here rather than in the surface because the registration is SCOPED: two products'
  // Send forms are different drafts, and a shared key would let one withdraw the other's
  // report. The surface owns the draft state and tells us when it stops being empty.
  //
  // Reported STRAIGHT into the registry rather than through `useState` + `useReportSettingsDirty`.
  // The state hop cost a whole commit: the surface's effect would `setDirty`, and only the render
  // that scheduled could run the reporting effect — so between a send clearing the form and that
  // second commit landing, the registry still said dirty (and, the other way up, a first keystroke
  // was unguarded for a commit). An exit fired in that window reads the stale answer. Both are one
  // frame wide and neither is visible on screen, which is why the pane's own test caught it and
  // nothing else did.
  const key = `messaging-send:${ecosystemId ?? "none"}`;
  const { reportDirty } = useSettingsDirty();
  const handleDirtyChange = useCallback(
    (next: boolean) => reportDirty(key, next),
    [key, reportDirty],
  );
  // Withdraw on unmount — and on a key change, so a pane switched to another product cannot
  // strand the old product's entry armed forever. Same contract `useReportSettingsDirty` gives.
  useEffect(() => () => reportDirty(key, false), [key, reportDirty]);

  return (
    <>
      <DetailHeaderActions
        api={{
          path: "/messaging/ecosystems/{id}/log",
          pathValues: { id: ecosystemId },
          title: "Messaging API",
        }}
        help={help}
      />
      <MessagingSurface
        status={{ data: status.data, isLoading: status.isLoading, isError: status.isError }}
        templates={templates}
        send={{
          mutate: (draft: SendMessageDraft, options) => send.mutate(draft, options),
          isPending: send.isPending,
          isSuccess: send.isSuccess,
          isError: send.isError,
        }}
        log={{ data: log.data, isLoading: log.isLoading }}
        page={page}
        onPageChange={setPage}
        enabled={ecosystemId != null}
        providerSetupHint={(channel) => (
          <>
            Connect a {channel === "email" ? "Postmark" : "Twilio"} integration on this product&apos;s
            Integrations tab.
          </>
        )}
        onDirtyChange={handleDirtyChange}
      />
    </>
  );
}
