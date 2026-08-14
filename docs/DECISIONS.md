# Decisions

Cross-cutting engineering decisions and directives that aren't tied to one file or area, so a comment alone
wouldn't surface them. A decision local to one file/view/patch belongs as a comment there instead, explaining why.

Append new entries at the top and date them. Don't edit past entries except to mark them superseded (and say by what).

## 2026-08-14: Sentry for error monitoring, via the theme

Right to Know reports errors to Sentry (org `oaf-org-au`, project `right-to-know`, EU region). Because the
Alaveteli fork must not carry site-specific changes, all of it lives in this theme:

- The sentry gems are runtime theme gems in `Gemfile.theme`, merged into Alaveteli's bundle at deploy time
  (`themes:pre_bundle_setup` in `config/deploy.rb`). They are absent from development, CI and spec runs, so any
  code touching Sentry must guard with `defined?(Sentry)`.
- `lib/sentry_init.rb` initialises the SDK and registers an ExceptionNotifier notifier. The notifier is the
  important part: Alaveteli's `ApplicationController` does `rescue_from Exception, with: :render_exception` and
  reports via ExceptionNotifier instead of re-raising, so sentry-rails' middleware alone would miss most web
  errors.
- The DSN and environment arrive as `SENTRY_DSN`/`SENTRY_ENVIRONMENT` env vars from the infrastructure repo's
  `shared/rails_env.rb` (see the matching entry in that repo's `docs/DECISIONS.md`). The environment is keyed
  off the deploy stage because staging and production both run `RAILS_ENV=production`.
- The existing exception notification emails (web-administrators@ plus Slack) stay on alongside Sentry for now;
  retiring them is a separate decision.
