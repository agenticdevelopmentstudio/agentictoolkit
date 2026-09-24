export { ProfileView, ProfileSkeleton, type ProfileViewProps } from './ProfileView'
export { ProfileNotFound } from './ProfileNotFound'
export { ProfileFallback, type ProfileFallbackProps } from './ProfileFallback'
export { useViewerPrincipal } from './useViewerPrincipal'
export type { ProfilePrincipal } from './types'

// `server.ts` is deliberately NOT re-exported here. It is the server half, reached only through
// its own `./profile-server` subpath, so a client component that imports this barrel cannot pull
// a server fetch into the browser bundle by accident. (The `server-only` package would enforce
// that mechanically; this workspace does not install it — see server.ts.)
//
// `normalize.ts` is not re-exported either, for the opposite reason: it is wire plumbing shared
// by both halves, not public surface.
