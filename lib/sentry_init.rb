# frozen_string_literal: true

# Sentry error monitoring for Right to Know.
#
# The sentry gems are theme runtime gems (see Gemfile.theme), merged into
# Alaveteli's bundle at deploy time, so they are absent from development, CI
# and spec checkouts - hence the defined? guards rather than requires. Without
# the gems this whole file is a no-op.
#
# The DSN and environment come from the SENTRY_DSN and SENTRY_ENVIRONMENT
# environment variables, which the SDK reads natively. They are set on the
# servers by the infrastructure repo via shared/rails_env.rb (loaded from
# Alaveteli's config/boot.rb, so web, sidekiq, daemons and cron all get them).
# With no SENTRY_DSN the SDK stays disabled. SENTRY_ENVIRONMENT is needed
# because staging and production both run RAILS_ENV=production. The release is
# auto-detected from Capistrano's REVISION file.
if defined?(Sentry)
  Sentry.init do |config|
    config.breadcrumbs_logger = %i[active_support_logger http_logger]
    config.send_default_pii = true
    config.traces_sample_rate = 1.0
  end

  # Alaveteli's ApplicationController rescues every exception itself
  # (rescue_from Exception, with: :render_exception) and reports through
  # ExceptionNotifier rather than re-raising, so sentry-rails' middleware
  # never sees most web errors. Registering a notifier catches that path and
  # Alaveteli's direct ExceptionNotifier.notify_exception call sites (mail
  # handling, Stripe webhooks, etc.) in one place. Anything the middleware
  # has already captured is skipped by Sentry.capture_exception itself - it
  # marks exception objects it has seen.
  if defined?(ExceptionNotifier)
    ExceptionNotifier.register_exception_notifier(
      :sentry,
      lambda do |exception, options|
        Sentry.with_scope do |scope|
          scope.set_rack_env(options[:env]) if options[:env]
          Sentry.capture_exception(exception)
        end
      end
    )
  end
end
