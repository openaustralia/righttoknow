# Decisions

Cross-cutting engineering decisions and directives that aren't tied to one file or area, so a comment alone
wouldn't surface them. A decision local to one file/view/patch belongs as a comment there instead, explaining why.

Append new entries at the top and date them. Don't edit past entries except to mark them superseded (and say by what).

## 2026-09-03: dormant accounts are handled in three ordered steps, and the blackhole address is the bounce address

The host's `users:destroy_unused` cron has been shipped disabled since #1031, because its first run
would destroy 2,732 of the site's 10,149 accounts and its "dormant for two years" guard reads
`last_sign_in_at`, a column added in 0.46 with no backfill. Four accounts have it set, so for anyone
who last signed in before the upgrade the guard sees a null and calls that "never signed in". Three
issues sequence getting to a point where the cron can be enabled honestly, and the order is the
decision worth recording:

- **Never-confirmed accounts go first, with no notice (#1096).** 969 of the 2,732 never confirmed
  their email address. `User#should_be_emailed?` requires `email_confirmed`, so there is no way to
  warn them and no reason to think a warning would arrive. Waiting gains nothing, so this pass is
  deliberately separate and unblocked: `DormantAccounts.destroy_never_confirmed`, a hard `destroy`
  like the host task, two years to stay consistent with it, `DRYRUN` on unless told otherwise. It
  logs account ids and creation dates, never addresses or names — the point is to hold less personal
  data, not to copy it into a terminal.
- **Bounce recording before any bulk send (#1094).** No account on the site has ever had a bounce
  recorded. Every mail the app sends sets `Return-Path` to the blackhole address
  (`ApplicationMailer#mail_user`), so **the blackhole, not `CONTACT_EMAIL`, is where bounces
  arrive** — which is the opposite of what upstream's install guide assumes, and the reason
  `script/handle-mail-replies` has never seen a single message here. It is also currently a Google
  Group that archives them. Fixing it is Workspace routing plus a Postfix pipe in the
  `infrastructure` repo, with no application code. Right to Know's sending reputation is what gets
  FOI requests delivered to authorities, so this lands before anything is mailed in bulk.
- **Notice to the accounts that can actually receive one (#1095).** `DormantAccountMailer` honours
  `should_be_emailed?`, so banned, opted-out and bounced accounts get no notice and are left to the
  cron, as upstream did on WhatDoTheyKnow. Recipients are tagged `dormant_account_notice:<date>`
  so a re-run can't mail them twice; user tags are used because `UserInfoRequestSentAlert` requires
  an `info_request_id` and these accounts have no requests by definition. Sends are capped per run
  and triggered by hand so the bounce rate can be watched between tranches rather than discovered
  afterwards. The email states a removal date computed as the run date plus 60 days, so **the cron
  must not be enabled before the latest date any tranche was told**.

The notice mailer's code may land before bounce recording works; its first live send may not.

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
