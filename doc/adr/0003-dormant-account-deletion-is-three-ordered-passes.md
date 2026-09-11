# Dormant account deletion is three ordered passes

The host's `users:destroy_unused` cron has been shipped disabled since #1031,
because its first run would destroy 2,732 of the site's 10,149 accounts and its
"dormant for two years" guard reads `last_sign_in_at`, a column added in 0.46
with no backfill. Four accounts have it set, so for anyone who last signed in
before the upgrade the guard sees a null and calls that "never signed in".

Three issues sequence getting to a point where the cron can be enabled
honestly, and the order is the decision worth recording:

- **Never-confirmed accounts go first, with no notice (#1096).** 969 of the
  2,732 never confirmed their email address. `User#should_be_emailed?` requires
  `email_confirmed`, so there is no way to warn them and no reason to think a
  warning would arrive. Waiting gains nothing, so this pass is deliberately
  separate and unblocked: `DormantAccounts.destroy_never_confirmed`, a hard
  `destroy` like the host task, two years to stay consistent with it, `DRYRUN`
  on unless told otherwise. It logs account ids and creation dates, never
  addresses or names — the point is to hold less personal data, not to copy it
  into a terminal.
- **Bounce recording before any bulk send (#1094).** No account on the site has
  ever had a bounce recorded, because bounces have never been arriving where
  `script/handle-mail-replies` looks — see
  [ADR-0004](0004-bounces-arrive-at-the-blackhole-address.md). Right to Know's
  sending reputation is what gets FOI requests delivered to authorities, so
  this lands before anything is mailed in bulk.
- **Notice to the accounts that can actually receive one (#1095).**
  `DormantAccountMailer` honours `should_be_emailed?`, so banned, opted-out and
  bounced accounts get no notice and are left to the cron, as upstream did on
  WhatDoTheyKnow. Recipients are tagged `dormant_account_notice:<date>` so a
  re-run can't mail them twice; user tags are used because
  `UserInfoRequestSentAlert` requires an `info_request_id` and these accounts
  have no requests by definition. Sends are capped per run and triggered by
  hand so the bounce rate can be watched between tranches rather than
  discovered afterwards. The email states a removal date computed as the run
  date plus 60 days, so **the cron must not be enabled before the latest date
  any tranche was told**.

The notice mailer's code may land before bounce recording works; its first live
send may not.

_Decided 2026-09-03; originally recorded in `docs/DECISIONS.md`._
