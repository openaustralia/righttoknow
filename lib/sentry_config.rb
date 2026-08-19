# frozen_string_literal: true

# Sentry error monitoring and APM for Right To Know
# (https://github.com/openaustralia/righttoknow/issues/1004).
#
# The sentry gems are only present in the server bundle, where Gemfile.theme
# is merged into the host Alaveteli Gemfile at deploy time, so do nothing
# when they aren't loaded (local development and CI).
if defined?(Sentry)
  Sentry.init do |config|
    # With no DSN configured the SDK stays disabled.
    config.dsn = AlaveteliConfiguration.get('SENTRY_DSN', nil)

    # Both servers run RAILS_ENV=production, so STAGING_SITE is what
    # distinguishes them. Read it with `get` and a default: it is not one of
    # AlaveteliConfiguration's DEFAULTS keys, so the `staging_site` reader
    # method does not exist and would raise NoMethodError here.
    config.environment =
      if Rails.env.production?
        AlaveteliConfiguration.get('STAGING_SITE', 0).to_i == 1 ? 'staging' : 'production'
      else
        Rails.env.to_s
      end

    config.breadcrumbs_logger = %i[active_support_logger http_logger]
    config.send_default_pii = true
    config.enable_logs = true

    # Fraction of requests traced for APM. Tune in general.yml without a
    # code change if quota becomes a problem.
    config.traces_sample_rate =
      AlaveteliConfiguration.get('SENTRY_TRACES_SAMPLE_RATE', 0.1).to_f
  end
end
