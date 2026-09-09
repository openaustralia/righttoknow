# Decisions

Cross-cutting engineering decisions and directives that aren't tied to one file or area, so a comment alone
wouldn't surface them. A decision local to one file/view/patch belongs as a comment there instead, explaining why.

Append new entries at the top and date them. Don't edit past entries except to mark them superseded (and say by what).

## 2026-09-07: external review applications are sent by email, with private details out-of-band

Right to Know can now send an application for external review of an FOI decision on the applicant's behalf
(issue #1107; federal only so far, where the reviewer is the Office of the Australian Information Commissioner
and the review is an "IC review"). Vocabulary, since the code and copy lean on it: **external review** is review
by a body other than the authority, and each jurisdiction has its own reviewer (`PublicBody#external_reviewer`);
**IC review** is the federal external review; a **deemed refusal** is an authority failing to decide within the
statutory period; the **private appendix** is contact/assistance detail sent to the reviewer by email but never
published. Decisions worth recording, because each had a real alternative:

- **The application is an email to FOIDR@oaic.gov.au, not a link-out to OAIC's web form.** OAIC's procedure
  direction says applications *should* (not must) use its online form, so email is valid, and sending it
  ourselves is what lets the request's state change reflect something we actually did. The email is sent from
  the request's own address, so the reviewer's correspondence (acknowledgements, s 55G consultations, the
  decision) threads back into the public request page - accepted deliberately, with a privacy warning on the
  form. Representatives applying on someone's behalf are out of scope and pointed at OAIC's own form.
- **Private details travel out-of-band, in three layers.** The contact telephone number (required by the
  direction, 2.9(b)) and other 2.11 details never enter the outgoing message body: (1) they're appended to the
  sent email only, via a non-persisted attribute read by the theme's `outgoing_mailer/followup` view;
  (2) they're persisted in the `followup_sent` event params, where admins can see them for resends but nothing
  renders them publicly (the same place core stashes classification messages); (3) the phone number gets a
  request-scoped `system` censor rule at send time, so it's redacted on display if the reviewer quotes it back.
  The rejected alternatives: a `requester_only` outgoing message (hides the grounds for review, the part that
  should be public) and a redacted-copy scheme (no existing mechanism). Consequence to know: an admin resend
  won't re-attach the appendix - the details are in the event params if that ever matters.
- **The form is structured; there is no editable letter body.** Decision type, decision date and disagreement
  compose the letter server-side (`ExternalReviewApplication`), so the required particulars can't be deleted,
  and validation is per-field rather than core's "did you edit the template" heuristic. Late applications get a
  soft warning (extensions of time exist under s 54T), never a block.
- **The state is `external_review`, jurisdiction-neutral, entered only by sending an application.** No
  self-reported "I applied via OAIC's form" path - people who apply directly can annotate, as before. For
  federal long-overdue requests the banner offers external review *instead of* internal review, because the
  direction (2.15) sends deemed refusals directly to the IC (this partially addresses #883). Adding another
  jurisdiction under #875 should mostly mean extending `PublicBody#external_reviewer`.

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
