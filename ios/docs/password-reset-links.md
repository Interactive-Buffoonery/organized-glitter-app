# Password reset links

Status: the release owner verified native iPad email-link reset, rejection of a
reused link, and desktop web fallback on September 27, 2026. The signed-in guard
and clarified recovery copy were then verified on the updated iPad build.

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

1. Opening a matching link while signed out presents password confirmation.
   While signed in, it shows a notice to sign out and reopen the email link;
   it does not present the form or sign the user out automatically. Links
   received during restoration wait for its result before being routed.
2. A missing or malformed token shows the same recovery screen as an invalid,
   expired, or reused token. The screen never displays the token.
3. The recovery screen explicitly asks for a new link. “Send a new reset link”
   opens the email-entry form and sends through the existing PocketBase endpoint.
   A well-formed used token is rejected on submission, not merely on opening.
4. A successful reset clears any local signed-in session and offers a direct
   return to sign in.
5. When a confirmation response is lost or the server fails, the result may be
   unknown. The app clears the local session and password fields, then offers
   sign-in with the new password or a fresh reset link.

The legacy `/reset-password?token=...` web route is not a native route. It
remains a web compatibility shim and redirects to the canonical path.

## Sign-in recovery contract

The backend's `users.authRule` is `verified = true`. Password authentication
rejected by that rule returns HTTP 403 with the exact message
`The request doesn't satisfy the collection requirements to authenticate.`
Only that response from `POST /api/collections/users/auth-with-password` maps
to email-verification recovery. Other 403 responses remain permission denials,
including missing or malformed response bodies. If the backend adds another
authentication-rule condition, it must provide a distinct verification signal
before clients can continue treating the generic rule rejection this way.

The backend migration `1789940324_enforce_verified_auth.js` and its disposable
`scripts/test-auth-verification.mjs` checks establish this source contract.

## Deployment gate

The app carries `applinks:organizedglitter.app`. On September 26, 2026, a direct
HTTPS GET of the canonical AASA file returned
`7CNK4YPCQX.com.interactivebuffoonery.organizedglitter` with the
`/auth/confirm-password-reset/*` component. The coordinated backend PR #261
merged on September 21, 2026. Neither observation verifies the deployed backend
revision or proves that iOS opens the link. Before claiming deployed native
support:

1. Verify a newly generated reset email on a physical iOS 18 or newer device,
   including app-open, web fallback, success, expired, and reused-token cases.
2. Check the native flow with VoiceOver.
3. Verify the deployed backend revision, then record it in
   `BackendContract.json`.

`BackendContract.json` remains unchanged because the deployed backend revision
has not been verified.

On September 27, 2026, browser GET and HEAD checks again returned 200 without
redirects, with `application/json` and the expected app identifier and path.
The canonical reset route also rendered the web reset form using a synthetic
invalid token. These checks do not establish real-email delivery or successful
reset completion.

During the same validation, the release owner inspected the deployed PocketBase
dashboard and confirmed `users.authRule = verified = true` and a reset-email
template using `{APP_URL}/auth/confirm-password-reset/{TOKEN}`. Neither setting
needed a change. These targeted checks do not establish the full deployed
backend revision.

The live web page's build identifier was
`851a929696fc8d3d1e8cfcb450aa26c394199d7a`, which includes the companion
reset-link PR #261. This identifies the web build, not the independently
deployed PocketBase hooks or configuration.

## Physical-device checklist

Use a development build of the current PR head and a disposable test account.
Record the device, OS, app revision, and results without recording credentials
or reset tokens.

1. Confirm PocketBase's application URL is `https://organizedglitter.app`.
   Request a real reset email and tap its button from the device's mail app.
   Confirm the native password-reset sheet opens.
2. Submit a valid new password. Confirm the success message, local sign-out,
   and sign-in with the new password. The old password must no longer work.
3. Open the same email link again and submit matching valid passwords. Confirm
   invalid/expired recovery and the option to request a new email.
4. Check a genuinely expired, unused link after its configured lifetime.
   Changing token text only tests an invalid token, not expiry. Do not shorten
   the production token lifetime for testing.
5. Request a separate fresh link and complete a reset in a desktop browser to
   verify the web fallback without an installed iOS app.
6. With VoiceOver enabled, traverse the form, trigger a validation error, and
   complete or reject a reset. Confirm meaningful labels, accessible actions,
   and outcome announcements without exposing token details.
