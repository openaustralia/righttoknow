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
    when Hash
      value.to_h { |key, item| [scrub_value.call(key), scrub_value.call(item)] }
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

  scrub_log = lambda do |log|
    log.body = scrub_value.call(log.body)
    log.attributes = scrub_value.call(log.attributes)
    log
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
    # Include user info, cookies, request headers, query parameters and
    # bodies for debugging context. Emails are scrubbed from breadcrumbs and
    # logs above.
    config.data_collection.tap do |data|
      data.user_info = true
      data.cookies = true
      data.http_headers.request = true
      data.http_headers.response = true
      data.url_query_params = true
      data.http_bodies = %i[incoming_request outgoing_request incoming_response outgoing_response]
      data.database_query_data = true
      data.queues = true
      data.graphql.document = true
      data.graphql.variables = true
      data.stack_frame_variables = false
      data.frame_context_lines = 3
    end
    config.before_send = scrub_breadcrumbs
    config.before_send_transaction = scrub_breadcrumbs
    config.before_send_log = scrub_log
    # Rails logs arrive via sentry-rails' structured logging. It is on by
    # default in 7.0 but off in 7.1, so set it explicitly. The logger patch
    # additionally forwards stdlib logging (Sidekiq's, and Rails.logger),
    # limited to warnings and above so request lines, with visitors' IP
    # addresses, don't flood Sentry.
    config.rails.structured_logging.enabled = true
    config.std_lib_logger_filter = ->(_logger, _message, level) { %i[warn error fatal].include?(level) }
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
