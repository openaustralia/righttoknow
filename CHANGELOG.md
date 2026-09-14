# Changelog

Developer-facing record of what shipped to
[Right To Know](https://www.righttoknow.org.au/), grouped by production
release (the theme has no version numbers of its own — a release is a
staging→production release pull request). Each bullet is one merged pull
request, credited to its author. Update this file as part of each release PR,
covering everything merged to `staging` since the previous release.

## 2026-09-03 (release #1084) — supports Alaveteli 0.46.7.0

* Theme updates for Alaveteli 0.46.7.0 (Ben Fairless, #1033)
* Add Dev Container and Docker dev environment (Ben Fairless, #1044)
* Move personal info gate from JS to CSS (Ben Fairless, #1070)
* Restore gap between page content and footer (Ben Fairless, #1071)
* Add themed maintenance downtime page (Ben Fairless, #1073)
* Switch Capistrano to reach hosts via SSM Session Manager (Ben Fairless,
  #1075)
* Fix staging URL in README to match actual www-staging hostname (Ian Heggie,
  #1080)
* Add /whatismyip trust-boundary diagnostic endpoint (Ian Heggie, #1081)
* Match the dev container database and mail service to Right to Know (Ben
  Fairless, #1085)

## 2026-08-21 (release #1064)

* Configure per-repo agent skill settings (Ben Fairless, #1057)
* Fix theme Gemfile injection during deploys (Ben Fairless, #1062)

## 2026-08-19 (release #1059)

* Add AGENTS.md, with CLAUDE.md and Copilot files pointing to it (Ian Heggie,
  #1046)
* Update Ruby version to 3.4.10 and add x86_64-linux to Gemfile.lock (Ben
  Fairless, #1048)
* Adopt the OAF standard footer (Ben Fairless, #1051)
* Accept Stripe promotion codes at Pro signup (Ben Fairless, #1052)
* Trim org-generic guidance from AGENTS.md (Ben Fairless, #1054)
* Restore login gate on Pro plan page (Ben Fairless, #1056)
* Send Right To Know errors and traces to Sentry (Ben Fairless, #1058)

## 2026-08-12 (release #1047)

* Update dead external links across help pages (Ben Fairless, #1034)
* Rename request browse wording to "request library" (Ben Fairless, #1039)
* Rewrite Help > About in library terms (Ben Fairless, #1040)
* Reframe home page copy around the request library (Ben Fairless, #1041)
* Reframe Pro feature list in library terms (Ben Fairless, #1042)

## 2026-08-07 (release #1030) — supports Alaveteli 0.45.8.0

* Remove issue and pull request templates (Ben Fairless, #1008)
* Refactor RuboCop configuration and deploy tasks (Ben Fairless, #1009)
* Bump concurrent-ruby from 1.3.6 to 1.3.7 (Dependabot, #1011)
* Restore Privacy Request Prompt for authorities that have many hidden
  requests (Ben Fairless, #1016)
* Update Staging with Production changes (Ben Fairless, #1017)
* Housekeeping, fixes & minor styling (0.45.8.0 stack 1/3) (Ben Fairless,
  #1019)
* Theme visual refresh: OAF footer, Fira Sans, mixins (0.45.8.0 stack 2/3)
  (Ben Fairless, #1020)
* Pro pricing & coupons for 0.45 Prices API (0.45.8.0 stack 3/3) (Ben
  Fairless, #1021)
* Fix spelling and grammar on public help pages (Ben Fairless, #1026)
* Restore announcement banner text colour (Ben Fairless, #1027)
* Remove inactive Lorem Ipsum from Pro Index Page (Ben Fairless, #1028)
* Remove branch restriction for Rubocop workflow (Ben Fairless, #1029)

## 2026-07-06 (release #1013)

* Support ssh ed25519 keys (Ian Heggie, #1013)

## 2026-06-01 (release #1010)

* Add deploy git tags (Ian Heggie, #1010)

## 2026-04-28 (release #1003)

* Add permissions to the Rubocop workflow (code scanning alert) (Ben
  Fairless, #996)
* Bump rack from 3.1.20 to 3.1.21 (Dependabot, #1000)
* Add Capistrano deployment configuration (Ben Fairless, #1001)
* Upgrade Capistrano to version 3 and update deployment scripts (Ben
  Fairless, #1002)

## 2026-03-31 (release #993)

* Bump rack from 3.1.19 to 3.1.20 (Dependabot, #987)
* .ruby-version file addition and .gitignore update (Ben Fairless, #992)
* Bump the bundler group with 2 updates (Dependabot, #997)

## 2026-03-18 (release #991)

* Update house rules for clarity and detail (Ben Fairless, #990)

## 2026-03-03 (release #988) — supports Alaveteli 0.43.2.1

* Theme updates for Alaveteli 0.43.2.1 (Ben Fairless, #976)

## 2025-12-30 (release #983)

* Update README for clarity and development setup (Ben Fairless, #979)
* Update .gitignore for macOS and Ruby (Ben Fairless, #980)

## 2025-12-02 (release #971)

* Move Legislation class definition for 'all' method outside Rails
  configuration (Ben Fairless, #970)

## 2025-11-26 (release #968)

* Add confidence_intervals.rb from core, and update it to use Statistics3
  (Ben Fairless, #967)

## 2025-11-24 (release #964) — supports Alaveteli 0.42.0.2

* Theme updates for Alaveteli 0.43 (Brenda Wallace, #958)

## 2025-11-07 (release #962)

* Clarify handling of personal information requests in house rules (Ben
  Fairless, #927)
* Add rubocop linting CI (Brenda Wallace, #952)
* BrowserStack Verification (Ben Fairless, #959)

## 2025-10-05 (release #957)

* Reduce number of paragraphs to make house rules easier to read (Ben
  Fairless, direct commit)

## 2025-09-25 (release #953)

* Update issue templates and CODEOWNERS (Ben Fairless, #951)

## 2025-09-16 (release #949)

* Fix GitHub Changes links formatting in house rules page (Ben Fairless,
  #943)
* Update indentation on lib/help_page_history.rb (Ben Fairless, #950)

## 2025-09-09 (release #946)

* Update Footer to include House Rules (Ben Fairless, #928)
* Fix GitHub issue template type field format from arrays to strings
  (Copilot, #941)
* Add CODEOWNERS file to define repository code owners (Ben Fairless, #945)

## 2025-09-02 (release #937)

* Add issue and pull request templates for consistent contributions (Ben
  Fairless, #925)
* Add reporting instructions to house rules page (Ben Fairless, #926)
* Update Contact Us Form (Ben Fairless, #935)
* Don't set history if a template doesn't exist (Ben Fairless, #936)
* Adding alt tags to support logos (Brenda Wallace, #938)

## 2025-08-26 (release #933) — supports Alaveteli 0.40.x

* Add _request_listing_via_event.html.erb to comment out request status
  (Brenda Wallace, #906)
* Remove twitter and facebook (Brenda Wallace, #908)
* Bring production branch changes into staging (Brenda Wallace, #909)
* Help page version history (Ben Fairless, #910)
* Minor theme change from 0.40 (Brenda Wallace, #913)
* Theme upgrades to 0.40.0.0 (Ben Fairless, #914)
* Refactor legislation handling in PublicBody and Legislation classes; add
  show view for public body (Ben Fairless, #930)

## 2025-08-02 (release #907)

* Add library wording to footer (Matthew Landauer, direct commit)

## 2025-03-18 (release #853)

* Updating help pages (coopzr, #853)
