"use client";

import { useStatusUser as useStatusSession, type StatusUser } from "../header-auth";

/**
 * Returns the current authenticated StatusUser, or null if unauthenticated / unknown.
 * A thin shape adapter over header-auth's useStatusUser — ONE queryFn owns the
 * /api/auth/me semantics (in particular: a transient non-OK response throws and keeps
 * the last-known session rather than reading as signed-out), so consumers can't drift.
 */
export function useStatusUser(): StatusUser | null {
  return useStatusSession().user;
}
