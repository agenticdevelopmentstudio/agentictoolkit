"use client";

import { useState, type ReactNode, type ReactElement } from "react";
import { Trash2 } from "lucide-react";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { AlertModal } from "@agenticdevelopertoolkit/ui/components/alert-modal";

export function ConfirmDialog({
  title,
  description,
  confirmLabel = "Delete",
  triggerLabel = "Delete",
  // The trigger's icon. Defaults to the trash can because every caller until now was a delete —
  // an action that is irreversible but NOT a delete (releasing a reserved name) needs to say so at
  // the trigger, or the confirmation is the first the operator hears of what they clicked.
  icon = <Trash2 className="size-4 mr-1" />,
  onConfirm,
  busy,
}: {
  title: string;
  description?: ReactNode;
  confirmLabel?: string;
  triggerLabel?: string;
  icon?: ReactNode;
  onConfirm: () => void;
  busy?: boolean;
}): ReactElement {
  const [open, setOpen] = useState(false);
  return (
    <>
      <Button
        variant="destructive-ghost"
        size="sm"
        onClick={() => setOpen(true)}
      >
        {icon}
        {triggerLabel}
      </Button>
      <AlertModal
        open={open}
        destructive
        title={title}
        description={description}
        cancelLabel="Cancel"
        onCancel={() => setOpen(false)}
        confirmLabel={confirmLabel}
        onConfirm={() => {
          setOpen(false);
          onConfirm();
        }}
        busy={busy}
      />
    </>
  );
}
