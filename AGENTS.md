# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, GitHub Copilot, and others) when working with code
in this repository. `CLAUDE.md` and `.github/copilot-instructions.md` point here so the guidance lives in one
place.

## What this repository is

This is **not** a standalone Rails app. It is the *theme package* for
[Right To Know](https://www.righttoknow.org.au/), the Australian deployment of
the open source FOI platform [Alaveteli](http://www.alaveteli.org/). Right To
Know runs on a [fork of Alaveteli](https://github.com/openaustralia/alaveteli)
with this theme checked out inside it at `lib/themes/righttoknow`. Everything
here — patches, views, assets, translations — is loaded into and overlaid onto
that host Alaveteli app at boot; none of it runs on its own.

Split of responsibility: if a change is Right To Know/Australia-specific (look
and feel, help page copy, AU jurisdiction rules, Pro pricing behaviour for this
site), it belongs here. If it's a general Alaveteli fix or feature, it should
go to the upstream [mysociety/alaveteli](https://github.com/mysociety/alaveteli)
repo instead — this fork won't deploy an unaccepted upstream change.

Small, low-capacity charity team (OpenAustralia Foundation) — favour simple,
low-maintenance solutions over ones that need ongoing attention.

This repo is worked on via terminal Claude Code and other editors alike — keep
guidance and commands in this file tool-agnostic (plain shell commands, not
editor-specific steps), both when following it and when adding to it.

## Tests and linting

Specs live in `spec/` but are **RSpec specs for the host Alaveteli app**, not
a self-contained suite — each one's first real line loads the host's
`spec/spec_helper` via a relative path (`../../../../spec/spec_helper`), which
only resolves when this repo is checked out at `alaveteli/lib/themes/righttoknow`.
They also set `ALAVETELI_TEST_THEME = 'righttoknow'` so the host's
`config/initializers/theme_loader` loads this theme during the run.

To run them, `cd` into the host Alaveteli checkout and run rspec from there,
pointing at this theme's spec files, e.g.:

```bash
cd ../alaveteli   # the host app, with this theme at lib/themes/righttoknow
bundle exec rspec lib/themes/righttoknow/spec/coupon_price_restriction_spec.rb
```

There is also a `test/` directory (Minitest/`ActiveSupport::TestCase`) but it
only contains the generated placeholder test — it is not actively used.

CI (`.github/workflows/rubocop.yml`) only runs Rubocop, not the spec suite —
lint locally with:

```bash
bundle exec rubocop
```

`.rubocop_todo.yml` holds a shrinking baseline of pre-existing offences; new
code should not add to it, and it's worth clearing entries you touch anyway.

## Architecture

### Theme loading (`lib/alavetelitheme.rb`)

The entry point the host app requires. It:

- Prepends this theme's `lib/views` to every controller's and mailer's view
  path (`prepend_view_path`), so an ERB file here overrides the host's view of
  the same name at the same relative path.
- Prepends this theme's `app/assets/{stylesheets,images,javascripts,fonts}` to
  the asset pipeline paths, so theme assets shadow host assets of the same name.
- Requires the four patch files below so their monkey-patches load at boot.
- Registers `lib/config/custom-routes.rb` with the host's
  `$alaveteli_route_extensions` so its routes get drawn.
- Wires FastGettext to check `locale-theme/en` for translations before falling
  back to the host's own `locale/`.

### Monkey-patch files (`lib/*_patches.rb`)

Each patches host Alaveteli classes via `class_eval` inside a
`Rails.configuration.to_prepare` block (required so patches survive class
reloading in development, per the comment in each file):

- **`model_patches.rb`** — the core of Right To Know's multi-jurisdiction
  support. Adds `PublicBody#jurisdiction` (derived from Alaveteli tags: `ACT`,
  `NSW`, `NT`, `QLD`, `SA`, `TAS`, `VIC`, `WA`, `federal`), and uses it to drive
  per-jurisdiction response deadlines (`reply_late_after_days`), working vs.
  calendar day counting, and which FOI legislation (`foi`/`eir`/`gipa`/`rti`)
  applies. See the Authorities/Jurisdictions tables in `README.md` for the full
  tag scheme — any change to jurisdiction logic should stay consistent with
  those tables.
- **`controller_patches.rb`** — patches `AlaveteliPro::PlansController` (adds
  the `coupon_preview` JSON endpoint, rate-limited per user, that live-previews
  a Stripe coupon's discount before checkout) and
  `AlaveteliPro::SubscriptionsController` (enforces a coupon's `interval`
  metadata restriction — see "Pro subscriptions" in `README.md` — by halting
  via `before_action` redirect *before* a subscription is created, since
  checking `flash[:error]` after the fact would still charge the customer).
  Both halves must stay in sync: whatever the preview accepts, checkout must
  actually honour, and vice versa (`spec/coupon_preview_parity_spec.rb` guards
  this).
- **`helper_patches.rb`** — mixes `AlaveteliPro::AlternativePriceTextHelper`
  (`lib/helpers/`) into `ActionView::Base`.
- **`patch_mailer_paths.rb`** — prepends theme mailer views onto
  `ActionMailer::Base`.

`lib/customstates.rb` and `lib/help_page_history.rb` are not required by
`lib/alavetelitheme.rb` directly:
- `customstates.rb` is Alaveteli's documented extension point
  (`InfoRequestCustomStates` / `RequestControllerCustomStates`) for adding
  custom request states — currently a no-op template (falls back to core
  behaviour) plus an unused `transferred` example state.
- `help_page_history.rb` is required at the top of `controller_patches.rb`
  (a plain `require 'help_page_history'` on line 3, above and outside the
  `to_prepare` block). It builds the "view history of this page on GitHub"
  link shown on theme-overridden help pages, pointing at this repo's
  `production` branch.

### Views (`lib/views/`)

Mirrors the host app's controller/view directory structure
(`lib/views/<controller>/<action>.html.erb` or `_partial.html.erb`). Any file
here takes priority over the host's file of the same relative path. Notable
areas: `help/*` (AU-specific help copy — house rules, requesting, unhappy,
etc.), `alaveteli_pro/*` (Pro marketing pages and plan/pricing views, including
role-specific marketing partials under `pages/marketing_roles/`), `general/*`
(frontpage, nav, footer, meta tags), `request/*` (request page overrides).

### Assets (`app/assets/`)

Standard Rails asset pipeline layout, prepended ahead of the host's own asset
paths (see above). `lib/alavetelitheme.rb` also explicitly registers
`event_tracking.js`, `personal_message_toggler.js`, and
`alaveteli_pro/coupon_preview.js` for precompilation.

### Translations (`locale-theme/en/app.po`)

Theme-specific/overriding translation strings, checked before the host's own
`locale/` catalogue (see FastGettext wiring above).

### Deployment

Deployed via Capistrano 3, run from *this* repository against the host
Alaveteli codebase (`Capfile`, `config/deploy.rb`, `config/deploy/{staging,production}.rb`).
See "Deployment" in `README.md` for the full command list
(`bundle exec cap staging deploy`, `deploy:migrate`, `deploy:restart`,
`xapian:destroy_and_rebuild_index`) and the one-time server bootstrap
(shared config files Capistrano expects to already exist under `shared/`).
Server provisioning (not deployment) lives in the separate `infrastructure`
repo.

### Seeding test data (`script/seed_test_data.rb`)

Populates a development/test Alaveteli instance with realistic-but-safe data
(real public authority names/tags pulled from production's public CSV export,
but every authority gets a dummy `@example.com` request email; dummy requests
only). Run via `rails runner` from the **host app**, not this repo — see
"Seeding test data" in `README.md` for exact commands and env vars
(`SEED_CSV_URL`, `SEED_CSV_PATH`, `SEED_BODIES_PER_TAG`,
`SEED_REBUILD_INDEX`). Refuses to run in `production`.

## Key domain knowledge

- **Jurisdictions**: Right To Know covers Federal plus all 8 AU states/territories,
  each with its own response deadline, working/calendar day counting, and
  governing legislation, all keyed off Alaveteli authority tags (see
  `model_patches.rb` and the Jurisdictions/Categories tables in `README.md`).
  When adding a new jurisdiction, `README.md`'s "Adding more jurisdictions"
  section lists every help page and view that also needs updating.
- **Authorities**: guidance on whether an agency warrants its own authority,
  state-name formatting conventions, request-email preference order, public
  notes, and short names is all in `README.md` under "Authorities" — read it
  before making bulk authority-data changes.
- **Pro coupons**: Stripe coupons restrict by product, not by individual price,
  so a monthly-only coupon can't be stopped from discounting the annual plan
  using Stripe's own `applies_to`. This theme layers its own restriction via
  a coupon `interval` metadata key, enforced identically in the checkout path
  and the live price-preview endpoint (both in `controller_patches.rb`). See
  "Pro subscriptions" in `README.md`.

## Working with AI tools

- If something here doesn't match what you're consistently seeing in the repo,
  flag the mismatch and ask which needs fixing (so it's fixed once and for
  all), presenting fixing the code as the easy default choice and updating
  this file as the alternative.
- Use Australian spelling and voice in new code (variable/constant names,
  comments, commit and error messages) and in prose.
- No em dashes, anywhere: code, docs, commit messages, chat. Use a hyphen,
  comma, or full stop instead.
- Don't flatter, over-praise, or write to keep the conversation pleasant. Skip
  stock enthusiasm like "Great question!" and focus on what actually helps.
- If the human's premise or approach looks wrong, say so before proceeding.
  Don't silently go along with it to avoid friction.
- Don't add abstractions, refactors, or generality beyond what was asked —
  this is theme/patch code overriding a much larger host app, so unrequested
  restructuring is especially likely to drift from what the host expects. Do
  offer to DRY up genuine repetition if it will make the code easier to
  understand.
- Prefer testing reality over mocking internals. The existing specs exercise
  real controllers/routes/views against StripeMock (a full fake Stripe, not a
  stub of app code), and that is the pattern to follow for new specs. Note
  that `spec/features/screenshots_feature.rb` is not that pattern: it is not
  named `_spec.rb`, so a default rspec run skips it, and its header comment
  lists an unmerged upstream Alaveteli PR, extra host gems and
  `config/general.yml` changes needed before it runs. But be pragmatic, not
  dogmatic: the existing suite does stub when the real alternative is
  genuinely worse, e.g. the rate limiter double in
  `coupon_preview_rate_limit_spec.rb` (the real limiter is PStore-backed
  shared state that `spec_helper` doesn't reset, which would make specs
  order-dependent) and the "expired coupon" double in
  `coupon_preview_spec.rb` (not a state StripeMock can construct). When you do
  reach for a stub, say why in a comment, the way those specs do, so a future
  reader can tell "chose not to test reality here, and here's the reason" from
  "didn't think to."
- Keep responses proportional to the question. A simple question gets a
  direct answer, not a wall of caveats.
- If a request could reasonably expand scope, list the extra ideas as bullets
  up front, separate from the implementation, then wait.
- If a request doesn't narrow the implementation down to one reasonable
  choice (e.g. exactly how a jurisdiction rule or a coupon restriction should
  behave), ask which behaviour is wanted before writing code — give a terse
  list of options with pros/cons rather than building for every
  interpretation.
- Check `docs/DECISIONS.md` for past cross-cutting decisions before assuming
  in an unfamiliar area of the repo; add a new entry there (rather than
  repeating it in multiple places) when a decision spans multiple files.
- When a commit message body covers more than one distinct point, use a
  markdown bullet list rather than one flowing paragraph.
- Stage commits, don't make them: `git add` the files, then write the
  proposed message (with the `Assisted-by:` trailer) to `.git/GITGUI_MSG`
  (used by `git gui`) and display it for copy/paste into an IDE. Check the
  file first; if it already has content, ask before overwriting rather than
  clobbering an existing draft. This keeps review and sign-off a deliberate
  separate human act, not a rubber stamp.
- Keep the future effect of any standing approval clearly scoped. Read-only
  calls (Read, grep, `git status`/`diff`/`log`) can be batched freely — no
  justification needed per call. File changes (Edit/Write, or Bash like
  `mv`/`rm`/`sed -i`) are different: state what's about to change and why
  before making it, one described step or clearly-announced group at a time.
  `git add` isn't covered by this — it's cheap to undo.
- The same scoping applies to Bash allow-patterns for multi-subcommand CLIs
  (`gh`, `git`): a prefix like `gh pr` covers both read-only `gh pr view` and
  mutating `gh pr create`/`merge`/`close`/`comment`. Prefer or request the
  pattern scoped to the exact safe subcommand used, not the shared prefix.
- Don't rely on this file for the org-wide contributing rules, they change and
  this copy will drift. Fetch the current ones before opening a PR or an issue:

  `gh api repos/openaustralia/.github/contents/.github/CONTRIBUTING.md -H "Accept: application/vnd.github.raw"`

  The PR and issue templates are org-level too, in the same repo under
  `.github/PULL_REQUEST_TEMPLATE.md` and `.github/ISSUE_TEMPLATE/`. Fill in the
  PR template rather than writing a freeform description. Between them they
  cover branch naming, draft PRs and assignees, DCO sign-off, the CLA, and AI
  disclosure, so don't restate any of that here.
- What is repo-specific, and overrides the org guide: branch from `staging` and
  target `staging`. This repo has no `main` branch, and the org guide names
  Right to Know as a project with its own workflow, so its "aim pull requests
  at `main`" does not apply. See "Contributing" in `README.md`.
- The human runs the commit, not the agent. The org guide requires a DCO
  `Signed-off-by` trailer (`git commit -s`) certifying the right to submit the
  change, and only a person can make that certification. That is the reason for
  staging commits rather than making them, above. Don't add `Signed-off-by` or
  `Co-authored-by` on an AI agent's behalf, and don't strip a human's.
- GitHub issues have no draft state. Don't create one directly, draft the
  title/body for the human to file themselves, unless they've explicitly asked
  you to create it this time.
- Never fabricate citations, figures, or URLs (e.g. authority names, request
  emails, legislation names) — say when something's unverified rather than
  guessing.
- Never commit real personal details, credentials, or secrets; use fictional
  placeholders in specs, `script/seed_test_data.rb` output, and examples
  (Australian Privacy Principles apply here as much as anywhere else in OAF).
- Keep all copy, help text, and authority notes non-partisan — Right To Know
  reports FOI activity and authority information neutrally, never implying
  endorsement or criticism of any agency, party, or position.
