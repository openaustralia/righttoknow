# frozen_string_literal: true

Rails.configuration.to_prepare do
  # Removed first for the same reason as WhatismyipController: to_prepare runs
  # again on every code reload against a fresh ApplicationMailer, and this
  # constant isn't Zeitwerk-managed, so redefining it would raise "superclass
  # mismatch".
  Object.send(:remove_const, :DormantAccountMailer) if
    Object.const_defined?(:DormantAccountMailer, false)

  ##
  # Tells the people behind dormant accounts that the account will be removed
  # unless they sign in (openaustralia/righttoknow#1095).
  #
  # Modelled on the host's SurveyMailer: a class method selects the cohort,
  # checks a per-account "already sent" guard, delivers, and records the send.
  # The store is a user tag rather than a UserInfoRequestSentAlert, because
  # that model requires an info_request_id and these accounts have no requests
  # by definition.
  #
  # Do not run a live send until bounce recording works (#1094). See
  # "Account housekeeping" in README.md and docs/DECISIONS.md (2026-09-03).
  # rubocop:disable Lint/ConstantDefinitionInBlock
  class DormantAccountMailer < ApplicationMailer
    # rubocop:enable Lint/ConstantDefinitionInBlock
    # Checked by name, so a re-run never mails the same account twice even
    # though each tag carries the date it was sent.
    TAG = 'dormant_account_notice'

    # How long people are given to sign in. The host cron must not be enabled
    # before the latest date any tranche was told, which is why the date goes
    # in the email rather than being left vague.
    NOTICE_PERIOD = 60.days

    # Mail is handed to a local Postfix, so a per-address failure is nearly
    # impossible: a bad address is accepted and bounced later. Several failures
    # in a row means the local pipe is broken and would fail for the whole
    # tranche, so stop rather than burning it.
    MAX_CONSECUTIVE_FAILURES = 5

    def notice(user, removal_date)
      @user = user
      @removal_date = removal_date

      # Only Reply-To. `mail_user` already sets Return-Path to the blackhole
      # address and adds the auto-generated headers, so setting those here as
      # SurveyMailer does would put each of them in the message twice.
      headers('Reply-To' => contact_from_name_and_email)

      mail_user(
        @user,
        subject: lambda {
          _('Your {{site_name}} account will be removed unless you sign in',
            site_name: site_name)
        }
      )
    end

    # Mail one tranche of the dormant cohort. Dry unless DRYRUN=0, and capped
    # at LIMIT accounts so the bounce rate can be watched between tranches
    # rather than discovered after the whole cohort has been mailed.
    def self.send_notices(dryrun: ENV['DRYRUN'] != '0',
                          limit: Integer(ENV.fetch('LIMIT', 200)),
                          out: $stderr)
      removal_date = Date.current + NOTICE_PERIOD
      sent = 0
      failed = 0
      consecutive_failures = 0

      DormantAccounts.scope.without_tag(TAG).order(:id).find_each do |user|
        break if sent >= limit
        # Skips banned, closed, unconfirmed, opted-out and bounced accounts.
        # They get no notice and are left to the host cron, as upstream did.
        next unless user.should_be_emailed?

        out.puts user.id

        if dryrun
          sent += 1
          next
        end

        if deliver_and_tag(user, removal_date, out)
          sent += 1
          consecutive_failures = 0
        else
          failed += 1
          consecutive_failures += 1
          if consecutive_failures >= MAX_CONSECUTIVE_FAILURES
            out.puts "Stopping: #{consecutive_failures} consecutive failures"
            break
          end
        end
      end

      out.puts summary(dryrun, sent, failed, removal_date)
    end

    # Tags only after a successful delivery, so an account that failed is
    # picked up by the next run.
    #
    # Rescues StandardError rather than a mail-specific class because
    # `raise_delivery_errors` is on and a sendmail failure surfaces as
    # Errno::EPIPE or similar. Logs the class, never the message, since a
    # delivery error can echo the address back.
    def self.deliver_and_tag(user, removal_date, out)
      notice(user, removal_date).deliver_now
      user.add_tag_if_not_already_present("#{TAG}:#{Date.current.iso8601}")
      true
    rescue StandardError => e
      out.puts "user #{user.id}: delivery failed (#{e.class})"
      false
    end
    private_class_method :deliver_and_tag

    def self.summary(dryrun, sent, failed, removal_date)
      if dryrun
        "DRY RUN: would notify #{sent} dormant accounts, " \
          "quoting a removal date of #{removal_date.iso8601}"
      else
        "Notified #{sent} dormant accounts (#{failed} failed). " \
          "They may be removed on or after #{removal_date.iso8601}"
      end
    end
    private_class_method :summary
  end
end
