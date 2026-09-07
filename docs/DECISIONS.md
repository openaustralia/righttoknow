# Decisions

Cross-cutting engineering decisions and directives that aren't tied to one file or area, so a comment alone
wouldn't surface them. A decision local to one file/view/patch belongs as a comment there instead, explaining why.

Append new entries at the top and date them. Don't edit past entries except to mark them superseded (and say by what).

## 2026-09-07: Australian mobile numbers are masked as text, never via a global censor rule

Issue #706 asked for automatic censoring of mobile numbers. Alaveteli has two mechanisms and they are not
interchangeable (see "Text masks vs censor rules" in `AGENTS.md` for the vocabulary): we chose a **text mask**,
registered by `lib/text_mask_patches.rb` through `AlaveteliTextMasker.add_mask`. Three decisions to preserve:

- **No global censor rule, ever, for this.** A global `CensorRule` is the only mechanism that reaches PDFs and
  other binary attachments, which makes it tempting, but creating one expires and re-masks every request on the
  site. When we tried this years ago it flooded the server with logs and left PDFs inaccessible, and
  WhatDoTheyKnow's theme goes as far as raising `NotImplementedError` when an admin tries to create one. If PDF
  coverage is ever wanted, the path is upstream: make core's `apply_binary_masks` (which already x's out email
  addresses in binaries, size-preservingly) customisable the way text masks now are.
- **Text content only, on purpose.** The mask covers message bodies and text/HTML attachments. PDFs and binaries
  keep core's email-only redaction; masks never reach the binary path even on upstream develop. The spec guards
  this boundary so crossing it is a conscious decision.
- **Tight pattern, tolerate misses.** The match/no-match table in `spec/au_mobile_number_mask_spec.rb` is the
  source of truth; the regex is whatever passes it. A missed number is recoverable with a per-request censor rule;
  an over-match silently corrupts the published record and, unlike a censor rule, leaves no admin trail. Known
  accepted edge: the bare international form (`61 4xx xxx xxx` without a `+`) can collide with an ABN that begins
  with 61 4.

Mechanics worth knowing: `add_mask` is an upstream API (mysociety/alaveteli@34a3d7be2, April 2026) that is not in
a tagged release yet, so our Alaveteli fork carries it as three cherry-picks; `text_mask_patches.rb` guards with
`respond_to?(:add_mask)` so the theme still boots against an older host, and the guard can go once a release
containing the API is merged into the fork. Message bodies pick the mask up at render time, but attachments are
masked once by `FoiAttachmentMaskJob` and stored, so pre-existing text attachments keep their old masking unless
deliberately re-masked - we chose not to bulk re-mask at deploy time.

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
