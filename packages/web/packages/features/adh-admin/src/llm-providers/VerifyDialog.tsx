"use client";

import { useRef, useState, type FormEvent } from "react";
import { CheckCircle2, TriangleAlert } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { DialogActions } from "@agenticdevelopertoolkit/ui/components/dialog-actions";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Field } from "@agenticdevelopertoolkit/ui/blocks/field";
import { Alert, AlertTitle, AlertDescription } from "@agenticdevelopertoolkit/ui/components/alert";
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { errorMessage } from "@agenticdevelopertoolkit/ui/lib/errors";
import {
  useVerifyProviderTemplate,
  type ProviderTemplate,
  type ProviderTemplateVerifyResult,
} from "../api/llm-providers";

/** A verify-result model entry is a bare name or an arbitrary object — render
 *  whichever identifying field is present, falling back to the raw JSON. */
function modelLabel(m: NonNullable<ProviderTemplateVerifyResult["models"]>[number]): string {
  if (typeof m === "string") return m;
  const id = m["id"];
  const name = m["name"];
  if (typeof id === "string") return id;
  if (typeof name === "string") return name;
  return JSON.stringify(m);
}

const PLACEHOLDER_RE = /\{[^}]+\}/;

/**
 * Probe a template's live endpoint with a caller-supplied key. The key never
 * leaves this form as anything but the one POST body — it is not cached by
 * React Query (useVerifyProviderTemplate has no queryKey) and is dropped the
 * moment the dialog closes (unmounting clears the local state).
 */
export function VerifyDialog({
  open,
  template,
  onClose,
}: {
  open: boolean;
  template: ProviderTemplate | null;
  onClose: () => void;
}) {
  const verify = useVerifyProviderTemplate();
  const [apiKey, setApiKey] = useState("");
  const [baseUrlOverride, setBaseUrlOverride] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const formRef = useRef<HTMLFormElement>(null);
  const busy = verify.isPending;
  const hasPlaceholders = template ? PLACEHOLDER_RE.test(template.baseUrl) : false;

  function close() {
    if (busy) return;
    setApiKey("");
    setBaseUrlOverride("");
    setFormError(null);
    onClose();
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!template) return;
    if (!apiKey.trim()) {
      setFormError("Enter an API key to probe with.");
      return;
    }
    setFormError(null);
    verify.mutate({ id: template.id, apiKey, baseUrl: baseUrlOverride });
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && close()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Verify {template?.name}</DialogTitle>
          <DialogDescription>
            Probe the live endpoint with a key of your own to confirm the base URL and auth spec
            actually work. The key is used for this one request only — it is never stored.
          </DialogDescription>
        </DialogHeader>
        <form ref={formRef} onSubmit={handleSubmit} className="flex flex-col gap-4">
          <Field label="API key">
            <Input
              type="password"
              autoComplete="off"
              value={apiKey}
              onChange={(e) => {
                setApiKey(e.target.value);
                if (formError) setFormError(null);
              }}
              placeholder="sk-…"
              className="font-mono"
            />
          </Field>
          <Field
            label="Base URL override"
            hint={
              hasPlaceholders
                ? `This template's base URL has {placeholders} (${template?.baseUrl}) — supply a concrete URL to probe.`
                : "Optional — leave blank to use the template's stored base URL."
            }
          >
            <Input
              value={baseUrlOverride}
              onChange={(e) => setBaseUrlOverride(e.target.value)}
              placeholder={template?.baseUrl}
              className="font-mono"
            />
          </Field>

          {formError && (
            <Alert variant="error">
              <TriangleAlert />
              <AlertDescription>{formError}</AlertDescription>
            </Alert>
          )}

          {verify.isError && (
            <Alert variant="error">
              <TriangleAlert />
              <AlertTitle>Couldn&apos;t reach the verify endpoint</AlertTitle>
              <AlertDescription>{errorMessage(verify.error)}</AlertDescription>
            </Alert>
          )}

          {verify.data && !verify.data.ok && (
            <Alert variant="error">
              <TriangleAlert />
              <AlertTitle>Verification failed</AlertTitle>
              <AlertDescription>{verify.data.error ?? "The provider rejected the probe."}</AlertDescription>
            </Alert>
          )}

          {verify.data?.ok && (
            <Alert variant="success">
              <CheckCircle2 />
              <AlertTitle>Verified</AlertTitle>
              <AlertDescription>
                {verify.data.models && verify.data.models.length > 0 ? (
                  <div className="mt-2 flex max-h-40 flex-wrap gap-1 overflow-y-auto">
                    {verify.data.models.map((m, i) => (
                      <Badge key={i} variant="success">
                        {modelLabel(m)}
                      </Badge>
                    ))}
                  </div>
                ) : (
                  "The provider accepted the key, but returned no model list."
                )}
              </AlertDescription>
            </Alert>
          )}

          <button type="submit" className="hidden" aria-hidden tabIndex={-1} />
        </form>
        <DialogActions
          cancelLabel="Close"
          onCancel={close}
          confirmLabel="Verify"
          onConfirm={() => formRef.current?.requestSubmit()}
          busy={busy}
          focusOnMount={false}
        />
      </DialogContent>
    </Dialog>
  );
}
