"use client";

import { useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { MessagingSurface, type SendMessageDraft } from "@agentic-toolkit/adh/messaging";
import { FeatureTitle } from "@agentic-toolkit/resource";
import { UnsavedChangesGuard } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-guard";
import {
  useMessageLog,
  useSendMessage,
  useMessagingStatus,
  useMessagingTemplates,
} from "../api/admin";

/**
 * The platform-wide Messaging tool: send email/SMS to any user via the hub's own
 * Postmark/Twilio config, with the full message log.
 *
 * Everything a reader sees is `MessagingSurface`, which the per-product Messaging pane
 * renders too — this file is the admin-scoped HALF: the `/messaging/{status,log,send}`
 * endpoints (gated by isAdmin()) instead of the per-ecosystem ones, and the words that
 * name that scope. The two used to be forked copies of one screen, and had drifted
 * (docs/ui/fleet-ui-audit.md, Tier 6).
 */
export function MessagingPane({ help }: { help?: ReactNode } = {}) {
  const [page, setPage] = useState(1);
  const status = useMessagingStatus();
  const { data: templates } = useMessagingTemplates();
  const log = useMessageLog(page);
  const send = useSendMessage();
  const router = useRouter();
  // The surface reports a half-composed message; this page has to catch it. There is no rail
  // host or SettingsDirtyProvider on this route to register with (the per-product pane has
  // both, which is why it reports through `useReportSettingsDirty` instead), so the guard is
  // mounted directly. Without it the shared prop is left dangling on this half of the split
  // and a click on the admin nav silently throws away a typed message.
  const [dirty, setDirty] = useState(false);

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <FeatureTitle title="Messaging" help={help} />
      <div className="flex min-h-0 min-w-0 flex-1 flex-col space-y-8 overflow-y-auto px-6 pb-8 pt-2">
        <UnsavedChangesGuard when={dirty} onNavigate={(href) => router.push(href)} />
        <MessagingSurface
          onDirtyChange={setDirty}
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
          userIdLabel="User ID"
          providerSetupHint={() => (
            <>Configure Postmark/Twilio as integrations on the hub ecosystem (Hub → Settings → Integrations).</>
          )}
        />
      </div>
    </div>
  );
}
