# Decisions

Cross-cutting engineering decisions and directives that aren't tied to one file or area, so a comment alone
wouldn't surface them. A decision local to one file/view/patch belongs as a comment there instead, explaining why.

Append new entries at the top and date them. Don't edit past entries except to mark them superseded (and say by what).

## 2026-08-24: the personal information gate fails open, and Sentry RIGHT-TO-KNOW-JS-5 is our canary

The new request form asks whether you're requesting personal information that should be confidential, and hides the
rest of the form until you answer "No". Until now that gate was applied by `personal_message_toggler.js`, a standalone
script that needed jQuery from the main `application.js` bundle. When the bundle failed to load, the gate didn't
degrade, it vanished: the form stayed visible and submittable, so someone could lodge a request for their own medical
or police records without ever seeing the warning (Sentry RIGHT-TO-KNOW-JS-4, issue #1065).

The gate is now pure CSS plus a server-rendered `checked` attribute, so it no longer depends on JavaScript at all.
Two decisions worth recording, because both are easy to undo by accident:

- **It fails open on purpose.** If the stylesheet fails to load, or a browser doesn't support `:has()`, the selector
  is dropped and the whole form is visible. We chose that over server-rendering the hidden state, which would fail
  closed and take the site's core function offline for a CSS failure. A rare missed privacy prompt is the lesser
  harm. Don't "fix" this by making the hidden state the server-rendered default.
- **Sentry RIGHT-TO-KNOW-JS-5 is left unresolved on purpose.** It's upstream Alaveteli's `request-attachments.js`
  throwing when the same bundle fails, and with no theme JavaScript left it's now the only signal we have that the
  bundle sometimes doesn't execute. If upstream ever guards that file silently, or someone is tempted to resolve
  JS-5, replace the signal before you do.

Related: `event_tracking.js` was deleted at the same time. It was dead twice over. Production has set `GA_CODE: ''`
since August 2025 (in the `infrastructure` repo), so the `unless ga_code.empty?` guard meant it was never included,
and the host app now loads `gtag.js`, which doesn't define `window.ga`, so its `typeof ga == 'function'` check would
have been false anyway. That left `lib/views/general/_before_body_end.html.erb` empty, so it's gone too and the
host's own partial resolves again.
