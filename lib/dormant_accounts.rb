# frozen_string_literal: true

##
# Housekeeping for accounts that have never been used, and the shared
# definition of the cohort the host's `users:destroy_unused` cron would
# destroy (openaustralia/righttoknow#1031, #1095, #1096).
#
# See "Account housekeeping" in README.md for how to run this, and
# docs/DECISIONS.md (2026-09-03) for why never-confirmed accounts are
# handled separately and without notice.
#
module DormantAccounts
  # Exactly the cohort of the host's `users:destroy_unused`
  # (alaveteli/lib/tasks/users.rake). Kept in one place so this pass and the
  # dormant-account notice (DormantAccountMailer) can never disagree about who
  # is at risk of deletion.
  #
  # `last_sign_in_at` is nil for every account that predates the 0.46 upgrade,
  # which is why the host cron is still disabled - see #1031.
  def self.scope
    time_range = ...2.years.ago
    User.unused.where(created_at: time_range, last_sign_in_at: [nil, time_range])
  end

  # Accounts in that cohort that never confirmed their email address. They
  # cannot be sent the notice at all (`User#should_be_emailed?` requires
  # `email_confirmed`), so there is nothing to wait for before deleting them.
  def self.never_confirmed
    scope.where(email_confirmed: false)
  end

  # Destroy the never-confirmed cohort. Dry unless DRYRUN=0, so a bare run is
  # always safe; LIMIT caps the batch, which is how to start a live run small.
  #
  # Prints one line per account as `id<TAB>created_at`, deliberately without
  # the email address or name - the point of the exercise is to hold less
  # personal data, not to copy it into a terminal and an issue comment.
  def self.destroy_never_confirmed(dryrun: ENV['DRYRUN'] != '0',
                                   limit: ENV['LIMIT'].presence&.to_i,
                                   out: $stderr)
    users = never_confirmed.order(:id)
    users = users.limit(limit) if limit

    users.pluck(:id, :created_at).each do |id, created_at|
      out.puts "#{id}\t#{created_at.iso8601}"
    end

    if dryrun
      out.puts "DRY RUN: would destroy #{users.count} never-confirmed accounts"
      return
    end

    out.puts "Destroyed #{destroy_users(users)} never-confirmed accounts"
  end

  # Same shape as the host task: clear the inbound TrackThing references that
  # have a foreign key but no association to cascade them, preload everything
  # so the cascade isn't an N+1, and silence the logger so a large run doesn't
  # write a line of SQL per row.
  #
  # `destroy!` rather than `destroy` so that a destroy blocked by a callback or
  # a foreign key fails the run instead of being counted as a success.
  def self.destroy_users(users)
    TrackThing.where(tracked_user_id: users.select(:id))
              .update_all(tracked_user_id: nil)

    destroyed = 0
    ActiveRecord::Base.logger.silence do
      users.preload(User.reflect_on_all_associations.map(&:name))
           .in_batches.each_record do |user|
        user.destroy!
        destroyed += 1
      end
    end
    destroyed
  end
  private_class_method :destroy_users
end
