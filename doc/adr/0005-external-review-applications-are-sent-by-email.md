# External review applications are sent by email, with private details out-of-band

Right to Know can now send an application for external review of an FOI
decision on the applicant's behalf (issue #1107; federal only so far, where the
reviewer is the Office of the Australian Information Commissioner and the
review is an "IC review"). Vocabulary, since the code and copy lean on it:
**external review** is review by a body other than the authority, and each
jurisdiction has its own reviewer (`PublicBody#external_reviewer`); **IC
review** is the federal external review; a **deemed refusal** is an authority
failing to decide within the statutory period; the **private appendix** is
contact/assistance detail sent to the reviewer by email but never published.

Decisions worth recording, because each had a real alternative:

- **The application is an email to FOIDR@oaic.gov.au, not a link-out to OAIC's
  web form.** OAIC's procedure direction says applications *should* (not must)
  use its online form, so email is valid, and sending it ourselves is what lets
  the request's state change reflect something we actually did. The email is
  sent from the request's own address, so the reviewer's correspondence
  (acknowledgements, s 55G consultations, the decision) threads back into the
  public request page - accepted deliberately, with a privacy warning on the
  form. Representatives applying on someone's behalf are out of scope and
  pointed at OAIC's own form.
- **Private details travel out-of-band, in three layers.** The contact
  telephone number (required by the direction, 2.9(b)) and other 2.11 details
  never enter the outgoing message body: (1) they're appended to the sent email
  only, via a non-persisted attribute read by the theme's
  `outgoing_mailer/followup` view; (2) they're persisted in the `followup_sent`
  event params, where admins can see them for resends but nothing renders them
  publicly (the same place core stashes classification messages); (3) the phone
  number gets a request-scoped `system` censor rule at send time, so it's
  redacted on display if the reviewer quotes it back. The rejected
  alternatives: a `requester_only` outgoing message (hides the grounds for
  review, the part that should be public) and a redacted-copy scheme (no
  existing mechanism). Consequence to know: an admin resend won't re-attach the
  appendix - the details are in the event params if that ever matters.
- **The form is structured; there is no editable letter body.** Decision type,
  decision date and disagreement compose the letter server-side
  (`ExternalReviewApplication`), so the required particulars can't be deleted,
  and validation is per-field rather than core's "did you edit the template"
  heuristic. Late applications get a soft warning (extensions of time exist
  under s 54T), never a block.
- **The state is `external_review`, jurisdiction-neutral, entered only by
  sending an application.** No self-reported "I applied via OAIC's form" path -
  people who apply directly can annotate, as before. For federal long-overdue
  requests the banner offers external review *instead of* internal review,
  because the direction (2.15) sends deemed refusals directly to the IC (this
  partially addresses #883). Adding another jurisdiction under #875 should
  mostly mean extending `PublicBody#external_reviewer`.
- **The reviewer's address is in code, and the host's `EXTERNAL_REVIEWERS`
  setting stays unused.** That key has been a single string since 2016 and
  nothing in the host reads it, so it can't carry one reviewer per
  jurisdiction; `PublicBody#external_reviewer` is the table instead (which is
  what #752 was really asking for). The consequence is that reviewer mail
  bypasses `PublicBody#request_email`, so `ExternalReviewOutgoingMessage#to`
  applies `OVERRIDE_ALL_PUBLIC_BODY_REQUEST_EMAILS` itself. Without that, a
  staging site whose only safeguard is the override would send real
  applications to the OAIC. The alternative, reading `EXTERNAL_REVIEWERS` as
  the federal address and treating blank as "off", was rejected because it
  adds a production config step that must not be forgotten and still breaks
  down at the second jurisdiction.

_Decided 2026-09-07; override bullet added 2026-09-14._
