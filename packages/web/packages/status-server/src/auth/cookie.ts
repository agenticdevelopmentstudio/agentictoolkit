import { setCookie, deleteCookie, getCookie } from 'hono/cookie';
import type { Context } from 'hono';
import type { StatusConfig } from '../config/port';

export const SESSION_COOKIE = 'status_auth';
const MAX_AGE_SECONDS = 30 * 24 * 60 * 60; // 30 days

/** Set the opaque session token in the httpOnly `status_auth` cookie. `SameSite=Lax`
 *  so the GitHub OAuth redirect back to /home still carries it; `Secure` in prod
 *  (https), opt-out via COOKIE_INSECURE=1 for http local dev / e2e. */
export function setSessionCookie(c: Context, token: string, config: StatusConfig): void {
  setCookie(c, SESSION_COOKIE, token, {
    httpOnly: true,
    secure: config.cookieSecure,
    sameSite: 'Lax',
    path: '/',
    maxAge: MAX_AGE_SECONDS,
  });
}

export function clearSessionCookie(c: Context): void {
  deleteCookie(c, SESSION_COOKIE, { path: '/' });
}

export function readSessionCookie(c: Context): string | undefined {
  return getCookie(c, SESSION_COOKIE);
}
