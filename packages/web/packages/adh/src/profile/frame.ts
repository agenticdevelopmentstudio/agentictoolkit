/** The box every state of a profile is drawn in: the profile itself (ProfileView), its loading
 *  skeleton (ProfileSkeleton), "not found" (ProfileNotFound), and the failed-load message
 *  (ProfileFallback). One string, so whichever state a route shows first, the next one replaces
 *  it in place instead of jumping.
 *
 *  A module of its own, not an export of ProfileView.tsx: tests mock `./ProfileView` wholesale
 *  (profileFallback.test.tsx), and a frame imported from there would vanish under the mock and
 *  throw in the two states that never render ProfileView at all. Not re-exported from the barrel
 *  either: a site that wants this frame wants one of those components, and a site-side copy of
 *  the class would stop matching the day it changes here. */
export const PROFILE_FRAME_CLASS = 'mx-auto max-w-2xl px-4 py-16 sm:px-6'
