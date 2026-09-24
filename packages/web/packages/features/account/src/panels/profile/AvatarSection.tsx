"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { User as UserIcon, Upload } from "lucide-react";

import {
  Avatar,
  AvatarImage,
  AvatarFallback,
} from "@agenticdevelopertoolkit/ui/components/avatar";
import { PrivacyLevelSelect } from "@agenticdevelopertoolkit/ui/components/privacy-level-select";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import {
  setPrivacyGrant,
  resolvePrivacyLevel,
  PRIVACY_KEY,
  type PrivacyGrant,
  type PrivacyLevel,
} from "@agentic-toolkit/data/profile";
import type { Me } from "../../api/auth";
import { DetailSection } from "@agentic-toolkit/resource";

// ── Helpers ────────────────────────────────────────────────────────────────────

function initialsOf(name: string | undefined | null): string {
  if (!name) return "";
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("");
}

// ── Component ──────────────────────────────────────────────────────────────────

export interface AvatarSectionProps {
  me: Me;
  grants: PrivacyGrant[];
}

export function AvatarSection({ me, grants }: AvatarSectionProps) {
  const qc = useQueryClient();

  const privacyMutation = useMutation({
    mutationFn: (level: PrivacyLevel) =>
      setPrivacyGrant("avatar", me.id, level),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: PRIVACY_KEY });
    },
  });

  const level = resolvePrivacyLevel(grants, "avatar", me.id);
  const displayName = me.name ?? me.email;
  const initials = initialsOf(displayName);

  return (
    <DetailSection title="Avatar">
      {/* In a Card like Public profile above it: a section whose controls float on the page
          background reads as a different form from the carded ones around it. */}
      <Card>
        <CardContent className="flex flex-col gap-4 sm:flex-row sm:items-center">
          {/* Avatar preview */}
          <Avatar className="size-20 shrink-0">
            {me.avatarUrl && (
              <AvatarImage src={me.avatarUrl} alt={`${displayName} avatar`} />
            )}
            <AvatarFallback>
              {initials || (
                <UserIcon
                  className="size-7 text-apt-text-muted"
                  aria-hidden="true"
                />
              )}
            </AvatarFallback>
          </Avatar>

          {/* Controls */}
          <div className="flex flex-col gap-3">
            {/* Avatar upload — intentionally deferred this branch */}
            <Button
              variant="outline"
              size="sm"
              disabled
              aria-disabled="true"
              className="w-fit cursor-not-allowed opacity-50"
            >
              <Upload data-icon="inline-start" />
              Upload coming soon
            </Button>

            {/* Privacy */}
            <div className="flex items-center gap-3">
              <span className="text-sm text-apt-text-muted">Visibility</span>
              <div className="w-40">
                <PrivacyLevelSelect
                  value={level}
                  onChange={(next) => privacyMutation.mutate(next)}
                  ariaLabel="Avatar visibility"
                  disabled={privacyMutation.isPending}
                />
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    </DetailSection>
  );
}
