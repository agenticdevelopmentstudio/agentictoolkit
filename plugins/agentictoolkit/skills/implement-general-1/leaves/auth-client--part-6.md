<!-- leaf: implement-general-1/auth-client--part-6 · source: auth-client.md -->

# Auth Client — continued (part 6)

**Rules** (cite as `implement-general-1/auth-client--part-6#<slug>`):

- `winui-3` SHOULD — HttpClient replaces fetch, with System.Text.Json for every JSON parse/serialize this component does inline …

## Platform Notes

- **React/Web**: This is the reference implementation. `fetch` for
  networking, `window.localStorage`/`window.sessionStorage` for persistence,
  `@simplewebauthn/browser`'s `startAuthentication`/`startRegistration` for
  WebAuthn ceremonies, and plain `window.location`/top-level navigation for
  every AS round-trip (no client-side router is involved — the SSO/central
  login flows are deliberately full-page navigations, not `fetch` calls,
  because the central session cookie is host-only on the AS host).
- **SwiftUI / AppKit / UIKit**: `URLSession` replaces `fetch`; the Keychain
  (not `UserDefaults`) is the idiomatic store for the access token, though
  this component's own decision to never persist the refresh token still
  applies — a native port keeps the refresh token cookie-equivalent
  server-side only, never in the Keychain either. `ASWebAuthenticationSession`
  (for the AS navigation/callback round-trip) and
  `ASAuthorizationPlatformPublicKeyCredentialProvider`/
  `ASAuthorizationSecurityKeyPublicKeyCredentialProvider` (for the WebAuthn
  ceremonies `mfa.ts`/`account-security.ts` run via `@simplewebauthn/browser`)
  are the platform equivalents. `NotificationCenter` or a `Combine`
  `PassthroughSubject` is the idiomatic equivalent of `onSessionChange`'s
  listener set.
- **Compose / Android**: `OkHttp` or `Ktor` replaces `fetch`;
  `EncryptedSharedPreferences` or Android `DataStore` is the idiomatic token
  store. `androidx.credentials` (Credential Manager) is the platform
  equivalent of the WebAuthn/passkey ceremonies. A `SharedFlow` or
  `LiveData` is the idiomatic equivalent of `onSessionChange`.
- **WinUI 3**: `HttpClient` replaces `fetch`, with `System.Text.Json` for
  every JSON parse/serialize this component does inline (`tokensFromResponse`,
  `extractErrorMessage`/`extractErrorCode`, every request/response body).
  `Windows.Storage.ApplicationData.Current.LocalSettings` is the equivalent
  of `localStorage` for the cached user object; a native port SHOULD still
  route the access token through `Windows.Security.Credentials.PasswordVault`
  rather than plain settings, since WinUI has no localStorage-equivalent
  XSS exposure to justify the web tradeoff — this is a stricter choice than
  the web source makes, not a divergence from its contract (the refresh
  token is still never stored, on any platform). `Task`/`async`-`await`
  replaces every `Promise`; an `ObservableCollection`/`INotifyPropertyChanged`-backed
  session object, or a C# `event`, is the idiomatic equivalent of
  `onSessionChange`'s subscriber set. `Windows.Security.Credentials.UI`
  (Windows Hello / passkeys) is the platform equivalent of the WebAuthn
  ceremonies; there is no equivalent of a top-level browser navigation for
  the SSO/central-login flows, so a WinUI port needs `WebAuthenticationBroker`
  or an embedded `WebView2` to carry the AS round-trip that `sso.ts` does
  with `window.location.href`.

