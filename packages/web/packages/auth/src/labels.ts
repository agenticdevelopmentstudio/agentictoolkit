// Pure display helpers shared across the auth UI (callbacks, login notice, the
// provider-link handler) so a new provider or error code is added in ONE place.

/** Human-friendly label for an OAuth provider slug (e.g. `github` → `GitHub`). */
export function providerLabel(slug: string): string {
  if (slug === 'github') return 'GitHub'
  if (slug === 'google') return 'Google'
  return slug.charAt(0).toUpperCase() + slug.slice(1)
}

// --- account-linking modal copy --------------------------------------------
// All user-facing strings for the reactive account-linking flow live here so the
// three modals (account-exists alert, post-login confirm, success) read
// consistently and a wording/provider change happens in ONE place.

/** Title of the `account_exists` modal shown on the OAuth callback. */
export const accountExistsTitle = 'Account already exists'

/** Body of the `account_exists` modal: tells the user to sign in with their
 *  existing method AND discloses that doing so will connect the just-attempted
 *  provider — this is where that expectation is first set. */
export function accountExistsLinkBody(providerSlug: string): string {
  return `Sign in with your email and password to continue — we'll connect your ${providerLabel(providerSlug)} sign-in so you can use it next time.`
}

/** Title of the post-login confirm modal that asks whether to link the provider. */
export function linkConfirmTitle(providerSlug: string): string {
  return `Add ${providerLabel(providerSlug)} to your account?`
}

/** Body of the post-login confirm modal. */
export function linkConfirmBody(providerSlug: string): string {
  return `Signing in again with ${providerLabel(providerSlug)} will add it as a sign-in method to your account, so you can use it to sign in next time.`
}

/** Primary-button label for the post-login confirm modal. */
export function linkConfirmAction(providerSlug: string): string {
  return `Continue with ${providerLabel(providerSlug)}`
}

/** Title of the in-progress modal while the link round-trip is completing. */
export function linkInProgressTitle(providerSlug: string): string {
  return `Connecting ${providerLabel(providerSlug)}…`
}

/** Body of the in-progress modal. */
export function linkInProgressBody(providerSlug: string): string {
  return `Connecting your ${providerLabel(providerSlug)} account…`
}

/** Title of the success modal shown once the provider is linked. */
export function linkSuccessTitle(providerSlug: string): string {
  return `${providerLabel(providerSlug)} connected`
}

/** Body of the success modal — the just-linked provider is now a sign-in method. */
export function linkSuccessBody(providerSlug: string): string {
  return `${providerLabel(providerSlug)} was added as a sign-in method to your account.`
}

/** Body of the success modal when the provider was already linked to THIS account
 *  (idempotent success, not an error). */
export function linkAlreadyLinkedBody(providerSlug: string): string {
  return `${providerLabel(providerSlug)} is already connected to your account.`
}

/** Title shown when a link round-trip can't be started or fails. */
export const linkFailedTitle = "Couldn't connect account"

/** Body shown when the link round-trip can't even be started (e.g. storage
 *  blocked, so the CSRF nonce can't be stashed). */
export function linkStartFailedBody(providerSlug: string): string {
  return `We couldn't start connecting your ${providerLabel(providerSlug)} account. Please try again.`
}

/** Title + body of the themed modal shown when user_login_disabled is on. */
export const loginDisabledTitle = "We're not open just yet"
export const loginDisabledBody = "The Hub isn't quite ready for visitors yet — please check back soon."

/** A backend OAuth `#error` code → a user-facing message. Unknown codes are
 *  surfaced verbatim so a failed sign-in stays diagnosable instead of collapsing
 *  to one string. */
export function oauthErrorMessage(code: string): string {
  if (code === 'account_exists')
    return 'An account already exists for this email — sign in with your email and password instead.'
  if (code === 'user_not_found') return 'Your account could not be found.'
  if (code === 'signups_closed') return "Sign-ups aren't open right now — please check back later."
  if (code === 'login_disabled') return loginDisabledBody
  if (code === 'password_disabled')
    return "Email and password sign-in isn't available here — use another sign-in method."
  return `Sign-in failed (${code})`
}
