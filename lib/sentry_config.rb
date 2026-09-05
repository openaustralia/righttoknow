# frozen_string_literal: true

# Sentry error monitoring, tracing and profiling for Right To Know
# (https://github.com/openaustralia/righttoknow/issues/1004), following the
# canonical OAF configuration in the infrastructure repo's docs/monitoring.md.
# Change the convention there first, then update every copy.
#
# The sentry gems are only present in the server bundle, where Gemfile.theme
# is merged into the host Alaveteli Gemfile at deploy time, so do nothing
# when they aren't loaded (local development and CI).
if defined?(Sentry)
  # Matches most email addresses. Used to scrub personal information from
  # breadcrumbs (e.g. log lines that mention a person's email address) in
  # line with the Australian Privacy Principles.
  email_pattern = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/

  scrub_value = lambda do |value|
    case value
    when String then value.gsub(email_pattern, '[FILTERED]')
    when Hash then value.transform_values { |v| scrub_value.call(v) }
    when Array then value.map { |v| scrub_value.call(v) }
    else value
    end
  end

  scrub_breadcrumbs = lambda do |event, _hint|
    event.breadcrumbs&.buffer&.each do |crumb|
      crumb.message = scrub_value.call(crumb.message) if crumb.message
      crumb.data = scrub_value.call(crumb.data) if crumb.data
    end
    event
  end

  Sentry.init do |config|
    # With no DSN configured the SDK stays disabled - that is the off switch.
    config.dsn = AlaveteliConfiguration.get('SENTRY_DSN', nil)

    # The Sentry environment is always the stage name, delivered as
    # SENTRY_ENVIRONMENT in general.yml by the infrastructure repo. Both
    # servers run RAILS_ENV=production, so falling back to the old
    # STAGING_SITE derivation keeps events labelled correctly if this deploys
    # before the provisioning change that adds the key. Read settings with
    # `get` and a default: they are not AlaveteliConfiguration DEFAULTS keys,
    # so the generated reader methods do not exist and would raise
    # NoMethodError here.
    config.environment =
      if (env = AlaveteliConfiguration.get('SENTRY_ENVIRONMENT', '')) != ''
        env
      elsif Rails.env.production?
        AlaveteliConfiguration.get('STAGING_SITE', 0).to_i == 1 ? 'staging' : 'production'
      else
        Rails.env.to_s
      end

    config.breadcrumbs_logger = %i[active_support_logger http_logger]
    # Include IP addresses, request headers and request parameters for
    # debugging context. Emails are scrubbed from breadcrumbs above.
    config.send_default_pii = true
    config.before_send = scrub_breadcrumbs
    config.before_send_transaction = scrub_breadcrumbs
    # Send Rails logs to Sentry as structured logs
    config.enable_logs = true
    config.enabled_patches << :logger

    # Fraction of requests traced for APM. Tune in general.yml without a
    # code change if quota becomes a problem.
    config.traces_sample_rate =
      AlaveteliConfiguration.get('SENTRY_TRACES_SAMPLE_RATE', 0.1).to_f
    # Relative to traces_sample_rate - profile 1 in 10 sampled transactions,
    # using vernier
    config.profiles_sample_rate = 0.1
    config.profiler_class = Sentry::Vernier::Profiler
  end

  # Attach the signed-in user to Sentry events so errors show who was
  # affected. The id only, never email or name - look the id up in the admin
  # backend if you need to contact someone about an error (Australian Privacy
  # Principles, and the canonical configuration in docs/monitoring.md).
  # Sentry's Rack middleware resets the scope every request, so this can't
  # leak between requests.
  Rails.configuration.to_prepare do
    ApplicationController.class_eval do
      before_action :set_sentry_user

      def set_sentry_user
        Sentry.set_user(id: current_user.id) if current_user
      end
    end
  end
end
