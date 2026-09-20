# Password reset links

Status: native implementation prepared; production association not yet verified.

## Contract

- Canonical URL: `https://organizedglitter.app/auth/confirm-password-reset/{TOKEN}`
- `{TOKEN}` is one opaque, non-empty path segment. The app percent-decodes it
  exactly once and does not impose a character set or length rule.
- The same URL opens the web reset flow when the app is not installed.
- Confirmation sends an unauthenticated `POST` to
  `/api/collections/users/confirm-password-reset` with `token`, `password`, and
  `passwordConfirm`. A `204` response means the reset succeeded.
- New passwords require at least eight characters, including an uppercase
  letter, a lowercase letter, and a number. The two password fields must match.

The application bundle identifier is
`com.interactivebuffoonery.organizedglitter`. The signing application
identifier verified from the generated app entitlement is
`7CNK4YPCQX.com.interactivebuffoonery.organizedglitter`. The web AASA entry must
use that full identifier and match `/auth/confirm-password-reset/*`.

## App transitions

1. Opening a matching link presents password confirmation above the current app
   state, including while the user is signed in.
2. A missing or malformed token shows the same recovery screen as an invalid,
   expired, or reused token. The screen never displays the token.
3. The recovery screen can request a new reset email.
4. A successful reset clears any local signed-in session and offers a direct
   return to sign in.
5. Offline and temporary server failures keep the form available for retry.

The legacy `/reset-password?token=...` web route is not a native route. It
remains a web compatibility shim and redirects to the canonical path.

## Deployment gate

The app carries `applinks:organizedglitter.app`, but the entitlement alone does
not make universal links work. Before claiming deployed native support:

1. Deploy the AASA file from the coordinated web change.
2. Verify the file over HTTPS with the exact application identifier and path.
3. Verify a newly generated reset email on a physical iOS 18 or newer device,
   including app-open, web fallback, success, expired, and reused-token cases.
4. Record the verified deployed backend revision in `BackendContract.json`.

`BackendContract.json` intentionally remains unchanged in this preparatory
change because the coordinated backend revision has not shipped or been
verified in production.
