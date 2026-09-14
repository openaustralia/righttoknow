# Bounces arrive at the blackhole address, not CONTACT_EMAIL

Every mail the app sends sets `Return-Path` to the blackhole address
(`ApplicationMailer#mail_user`), so **the blackhole, not `CONTACT_EMAIL`, is
where bounces arrive** — which is the opposite of what upstream's install guide
assumes, and the reason `script/handle-mail-replies` has never seen a single
message here, and no account on the site has ever had a bounce recorded. The
blackhole is also currently a Google Group that archives them.

Fixing it (#1094) is Workspace routing plus a Postfix pipe in the
`infrastructure` repo, with no application code. It has to be in place before
any bulk send to accounts, which is why it sits where it does in the ordering —
see [ADR-0003](0003-dormant-account-deletion-is-three-ordered-passes.md).

_Decided 2026-09-03; originally recorded in `docs/DECISIONS.md`._
