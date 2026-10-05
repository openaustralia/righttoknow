# The personal information gate fails open

The new request form asks whether you're requesting personal information that
should be confidential, and hides the rest of the form until you answer "No".
The gate is pure CSS (a `:has()` selector) plus a server-rendered `checked`
attribute — it deliberately does not depend on JavaScript, after the previous
`personal_message_toggler.js` implementation vanished entirely whenever the
jQuery-carrying `application.js` bundle failed to load (Sentry
RIGHT-TO-KNOW-JS-4, issue #1065), leaving the form visible and submittable
with no privacy warning at all.

**It fails open on purpose.** If the stylesheet fails to load, or a browser
doesn't support `:has()`, the selector is dropped and the whole form is
visible. We chose that over server-rendering the hidden state, which would
fail closed and take the site's core function offline for a CSS failure. A
rare missed privacy prompt is the lesser harm. Don't "fix" this by making the
hidden state the server-rendered default.

The canary that tells us the JS bundle sometimes fails is a deliberately
unresolved Sentry issue — see
[ADR-0002](0002-leave-sentry-js5-unresolved-as-canary.md).

## Related

`event_tracking.js` was deleted at the same time. It was dead twice over:
production has set `GA_CODE: ''` since August 2025 (in the `infrastructure`
repo), so the `unless ga_code.empty?` guard meant it was never included, and
the host app now loads `gtag.js`, which doesn't define `window.ga`, so its
`typeof ga == 'function'` check would have been false anyway. That left
`lib/views/general/_before_body_end.html.erb` empty, so it's gone too and the
host's own partial resolves again.

_Decided 2026-08-24; originally recorded in `docs/DECISIONS.md`._
