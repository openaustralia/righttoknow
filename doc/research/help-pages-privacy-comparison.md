# WhatDoTheyKnow privacy page compared with ours

Research for [#1141](https://github.com/openaustralia/righttoknow/issues/1141), under #1138 and for #867.
Related issues read: #728 (postal address wording) and #1069 (Google Analytics on the Pro legal page).
This note makes no recommendation on whether to rewrite anything.

## Sources and limits

- WhatDoTheyKnow (WDTK): https://www.whatdotheyknow.com/help/privacy, read on 2026-10-22.
- `curl` and WebFetch both received an HTTP 403 Cloudflare challenge page.
- A Playwright browser session loaded the page once the challenge cleared on its own, and the page text was read from that.
- Everything said below about WDTK comes from that text.
- Ours: `lib/views/help/privacy.html.erb` and `lib/views/alaveteli_pro/pages/_legal.html.erb`, read in this repository.
- The live righttoknow.org.au pages were not fetched.
- The theme view overrides the host view of the same path, so the ERB files should match what is served, but that is inferred.
- Evidence about what the site does comes from `lib/views/general/_before_head_end.html.erb`, `lib/sentry_config.rb`, `doc/adr/0001`, `doc/adr/0003`, `README.md`, `AGENTS.md` and the issue bodies.
- Issue bodies are claims by their authors and are marked as such.
- WDTK is run by a UK charity and its page is written around UK GDPR and the ICO.
- Its legal references are not directly comparable with Australian law, and this note does not assess either legal position.

## 1. Topics WDTK covers that ours does not

Ours has no equivalent text on any of these.

- **Who runs the service and its registrations.** WDTK names the charity and points to registrations with the Information Commissioner and the Charity Commission.
- **A list of personal information collected.** WDTK lists name, email address and IP address for an FOI request, and email address, name and message content for support email.
- **Support email handling.** WDTK says support mail goes to a central mailbox handled by volunteers under security protocols.
- **Administrator access to email addresses.** WDTK says site administrators may access an email address to administer the site and may contact users about their use of the site, including people who made an interesting request, for blog posts.
- **IP address handling.** WDTK says IP addresses are logged automatically, are not normally seen by a person, and are not shared except where required by law.
- **Server logs and their retention.** WDTK says web server logs hold client IP, submitted data, time, page, browser version and referrer, and are routinely kept for 60 days.
- **Cloudflare.** WDTK says visits pass through Cloudflare, that IP addresses are processed there for security, and that Cloudflare may set essential cookies.
- **Cookies.** WDTK lists six named cookies with typical content and expiry.
- **Analytics.** WDTK describes its analytics service, the settings it uses, and a browser plugin to opt out.
- **Third-party processor for summaries and classification.** WDTK describes a subprocessor (Exoscale) running open-weight language models over published correspondence, with processing in the EEA.
- **Email domain check.** WDTK says the domain part of an email address (after the @ sign) may be sent to a third-party service to confirm eligibility.
- **Research use.** WDTK describes internal research, release of non-personal data to external researchers, a Research Data Release Policy, excluded attachment types, a three month delay and a register of researchers.
- **Encrypted transfer to the regulator.** WDTK describes AES encryption with at least a 256 bit key for sensitive material sent to the Information Commissioner, with the password sent separately.
- **Children and young people.** WDTK has a section saying the site is not designed for people under eighteen, how it handles their personal data, and that it treats erasure requests from or for them as rights-based requests.
- **Consequences of using the service.** WDTK lists search engine results and contact from others, including the press, via the user contact facility.
- **What accounts and public profiles hold.** WDTK lists what a public profile page shows and says alert subscriptions are visible only to the signed-in user.
- **Retention periods.** WDTK says request data is kept indefinitely, profile content is removed after 6 months of inactivity, unused accounts are deleted after 2 years, support email is kept for 2 years (30 days for misdirected sensitive mail), and breached material has its own schedule.
- **Material released in breach of data protection law.** WDTK describes volunteer download limits (deleted within four hours), a four week hold for the regulator, and escalation to staff.
- **Legal basis for processing.** WDTK states the bases it relies on, including legitimate interest, legal obligation and journalism-related provisions.
- **Formal rights.** WDTK sets out erasure, access, objection and complaint, with the regulator's contact details and a registration number.
- **Removal of public servants' personal information.** WDTK distinguishes decision-makers and responders from junior, non-decision-making staff.
- **Pseudonym alternatives.** WDTK lists alternatives such as a different form of name, a maiden name, an organisation name, a friend, or asking WDTK.
- **A review commitment and change history.** WDTK says the pages are kept under review and points to a change synopsis in a GitHub repository.
- **A postal workaround.** WDTK says a request can be marked "They are going to reply by postal mail" to get an address for private postal details.

## 2. Topics ours covers that WDTK does not

- **Emails from the operating charity.** Ours says people also receive emails from OpenAustralia Foundation, which can be unsubscribed from without affecting alerts.
- **Revealing an email address when messaging another user.** Ours says a message to another user reveals the sender's email address and that the person will be told. WDTK mentions a user contact facility only as a consequence of publishing a request, and does not say what is revealed.
- **Australian FOI Act and OAIC guidance.** Ours cites the Federal Information Commissioner's guidelines on identity and says this site is named in them.
- **Help for authorities with large files.** Ours links to the FOI officer help for uploading large files directly to a request.
- **A line manager request for removing an official's name.** Ours requires a request from the official's line manager that shows a perceived risk and efforts to conceal the name on the organisation's own website.
- **Pro terms.** `_legal.html.erb` covers age (18 or over), accounts, termination and what happens to private requests on cancellation, payment and billing, no availability guarantee, and liability limits.
- **A named payment processor.** Ours names Stripe and links to its privacy policy. WDTK's page has no payment section.

## 3. Both cover the topic, with different specificity

| Topic | WDTK | Ours |
| --- | --- | --- |
| Email address visibility | Says it is not shared with the authority or published, names the exceptions (administrators, occasional contact), and describes the generated per-request address. | Says it is not disclosed unless obliged by law or asked, and that the authority sees a unique address at the incoming email domain. No administrator exception is stated. |
| Other uses of email | States emails are for requests, alerts or things the person authorises. | Same, and adds the charity emails. |
| Why names are public | Gives three reasons, including that people "think twice before making a request". | Gives fairness to the named public servant and helping people get in touch. |
| Pseudonyms | Says the real name is required for a valid request in law, cites guidance, warns it may block a complaint to the regulator, and lists alternatives. | Says "Yes, you can use a pseudonym", warns it may make review impossible, and quotes the OAIC guidelines that identity need not be proven. No alternatives. |
| Postal address | Argues the address-for-correspondence provision is met by the request email address and quotes two regulator documents. | States an email address is sufficient by law and links to the OAIC guidelines. No statement of which jurisdictions this applies to. |
| Deleting requests | Explains archive value, asks people to reconsider removing their name, and says formal erasure requests will be considered. | Says requests are not deleted and names may be removed or changed in exceptional circumstances. No named rights or process. |
| Removing personal information | Says removal requests are balanced against legitimate interests and cites regulator guidance. | Says to describe exactly what and where, and that sensitive information accidentally posted will usually be removed. |
| Officials' names | Distinguishes senior and junior staff. | Says there is a strong public interest in names and removal is only in exceptional circumstances. |
| Attachments that cannot be edited | Says WDTK is generally unable to edit attachments and asks for replacement responses. | Says PDFs, Word and Excel files cannot easily be edited and authorities are asked to resend. |
| Contacting about problems | Describes a complaints procedure and a regulator complaint route. | Points to the contact page. |
| Privacy in Pro | Not applicable. | A four paragraph "Privacy" section: data used solely to administer the service, not disclosed unless compelled by law, emails only about use, cookies and analytics, and Stripe. |

## 4. Statements in our pages that look inaccurate or stale

Each item says what was checked and what was not.

1. **Google Analytics on the Pro legal page.**
   - `_legal.html.erb` lines 240 to 243 say "we sometimes use cookies and Google Analytics to help us make our websites better, you can block this if you want to."
   - Issue #1069 says Google Analytics stopped in August 2025 because `GA_CODE` is empty in the infrastructure repo.
   - `doc/adr/0001` says the same ("production has set `GA_CODE: ''` since August 2025").
   - In this repo, `_before_head_end.html.erb` loads Plausible in production for `www.righttoknow.org.au`, and no Google Analytics script.
   - The infrastructure repo was not read for this task, so the production setting is taken from the issue and the ADR.
2. **"Cookies ... you can block this" implies all cookies are optional.**
   - #1069 says the site sets session cookies needed to stay signed in, and that blocking them breaks it.
   - That claim is by the issue author.
   - No cookie inventory for Right to Know was made in this task, so which cookies the site sets is unverified.
3. **Pro page says personal data is used "solely for the purpose of administering the service" and not disclosed "to anyone else unless we are compelled to by law".**
   - The same page names Stripe.
   - `_before_head_end.html.erb` loads Plausible, and Sentry browser monitoring with `sendDefaultPii: true` (comment: "Send user IP with events"), with the signed-in user's numeric id attached.
   - `lib/sentry_config.rb` scrubs email addresses from breadcrumbs and sends the user id only.
   - Whether these count as administering the service, or as disclosure, is a judgement that is not made here.
   - What Stripe, Plausible and Sentry receive was not checked against those providers' documentation.
4. **Postal address wording (#728).**
   - `privacy.html.erb` says "An email address is sufficient by law".
   - Issue #728 says some states need a postal address, so the wording is not accurate everywhere.
   - That is the issue author's claim, and no state legislation was checked here.
   - The anchors `full_address` and `postal_answer` are the ones the issue names.
5. **The pseudonym statement is not qualified by jurisdiction.**
   - Ours says "by law, you don't have to" use a real name, and that a pseudonym is allowed.
   - The site covers federal and eight state and territory schemes (AGENTS.md).
   - Whether the same holds in each was not checked.
6. **The OAIC quotation and link.**
   - Ours quotes the guidelines in `privacy.html.erb` line 60.
   - A commit on 2026-08-07 updated dead external links on help pages.
   - The link and the quoted sentences were not fetched here, so they are unverified.
7. **No mention of account deletion.**
   - Ours says nothing about dormant or unused accounts being deleted.
   - `doc/adr/0003` and `README.md` describe a two year dormant account deletion done by the host cron, which the ADR (decided 2026-09-03) says was shipped disabled.
   - Whether it is enabled now was not checked.
   - So the page is silent rather than wrong, but the repo shows a retention practice that is planned or in progress.
8. **Pro terms: billing "on a monthly basis".**
   - `_legal.html.erb` says the plan "is billed in advance on a monthly basis".
   - AGENTS.md refers to an annual plan and to coupon restrictions between monthly and annual plans.
   - This is not a privacy statement, but it is on a page in scope.
   - Current plan terms were not checked against the plans page or Stripe.
9. **Dead tracking calls (code, not copy).**
   - #1069 notes `track_analytics_event` is still called from `lib/views/request/new.html.erb` and `lib/views/request/_act.html.erb`.
   - Both files were confirmed to still contain the call.
   - The #1069 author says it is a no-op in the host app, which was not verified.

## Unverified in this task

- What cookies Right to Know sets, and their expiry.
- Whether Right to Know logs IP addresses, and for how long.
- Whether and how Cloudflare sits in front of the site, and what it processes.
- What Stripe, Plausible and Sentry receive and retain.
- The current production state of Google Analytics and of the dormant account cron.
- Whether any Australian legal requirement applies to OAF.
  Issue #867 records the CEO's view that the Privacy Act threshold is not met, and this task did not check that against the Act.
- Whether any statement on the live site differs from the ERB files.
