# frozen_string_literal: true

##
# Runtime-conflict handler for FoiAttachmentMaskJob
# (openaustralia/righttoknow#1115).
#
# The job's `:until_and_while_executing` strategy holds a `:runtime` Redis lock
# while a mask runs and releases it in an `ensure`. A hard death (SIGABRT from
# a watchdog, SIGKILL, OOM) skips the `ensure`, so the lock sits in Redis until
# its TTL expires and every re-enqueued job aborts on it in silence. Meanwhile
# the attachment's wait page polls forever.
#
# When a new job collides with a runtime lock, this decides which kind it is:
#
# - live: another Sidekiq thread is actually masking this attachment right
#   now. `Sidekiq::Workers` lists an in-flight FoiAttachmentMaskJob for the
#   same attachment. Leave the lock alone; the conflict is the strategy doing
#   its job.
# - stranded: nothing is running behind the lock. Report it to Sentry and
#   delete it, so the wait page's next poll enqueues a job that acquires it.
#
# `Sidekiq::Workers` is fed by Sidekiq's 5 s heartbeat, so a job that started
# a moment ago may not be listed yet. Any lock younger than HEARTBEAT_GRACE_MS
# is therefore treated as live without looking. The heartbeat also leaves a
# dead process's work list in Redis for up to 60 s, which only ever errs on
# the side of "live". The check-then-delete against Redis is not atomic, so
# a job that reacquires this exact key between the checks and the delete can
# in principle have its lock removed too; the worst misclassification in
# either case is one duplicate mask run, never lost data.
#
# See doc/adr/0005-sidekiq-runs-without-a-systemd-watchdog.md.
#
class MaskJobRuntimeConflict
  HEARTBEAT_GRACE_MS = 60_000

  def self.call(job)
    new(job).call
  end

  def initialize(job)
    @job = job
  end

  def call
    remaining_ttl_ms = lock_manager.get_remaining_ttl_for_resource(lock_key)
    return if remaining_ttl_ms.nil?
    return if too_young?(remaining_ttl_ms)
    return if in_flight?
    return unless still_stranded?(remaining_ttl_ms)

    lock_manager.delete_lock(lock_key)
    report_stranded(remaining_ttl_ms)
  rescue StandardError => e
    Rails.logger.warn(
      "MaskJobRuntimeConflict failed for #{lock_key}: #{e.class}: #{e.message}"
    )
    Sentry.capture_exception(e) if defined?(Sentry)
    nil
  end

  private

  attr_reader :job

  def attachment
    job.arguments.first
  end

  def lock_key
    job.runtime_lock_key
  end

  def lock_manager
    ActiveJob::Uniqueness.lock_manager
  end

  # A lock created before this theme capped the runtime TTL at 30 minutes
  # (a hard death under the old 1-day gem default) can still have more time
  # remaining than the current cap allows for. `runtime_lock_ttl -
  # remaining_ttl_ms` would go negative for one of those and read as
  # younger than the grace period, so a lock with more time left than the
  # current cap is treated as old rather than freshly created.
  def too_young?(remaining_ttl_ms)
    configured_ttl_ms = job.lock_strategy.runtime_lock_ttl
    return false if remaining_ttl_ms > configured_ttl_ms

    (configured_ttl_ms - remaining_ttl_ms) < HEARTBEAT_GRACE_MS
  end

  # Narrows, but does not close, the gap between reading this lock and
  # deleting it: a job that legitimately reacquires the same key resets its
  # TTL to the full runtime_lock_ttl, so a remaining TTL that has grown
  # since the first reading means someone new is holding it now.
  def still_stranded?(first_reading_ms)
    latest_ms = lock_manager.get_remaining_ttl_for_resource(lock_key)
    latest_ms && latest_ms <= first_reading_ms
  end

  def in_flight?
    global_id = attachment.to_global_id.to_s

    Sidekiq::Workers.new.any? do |_process_id, _thread_id, work|
      payload = work['payload']
      next false unless payload.is_a?(Hash)

      payload['wrapped'] == 'FoiAttachmentMaskJob' &&
        payload.dig('args', 0, 'arguments', 0, '_aj_globalid') == global_id
    end
  end

  def report_stranded(remaining_ttl_ms)
    Rails.logger.warn(
      "FoiAttachmentMaskJob runtime lock for FoiAttachment #{attachment.id} " \
      "was stranded (no in-flight job); deleted #{lock_key}"
    )
    return unless defined?(Sentry)

    Sentry.capture_message(
      'FoiAttachmentMaskJob runtime lock stranded and deleted',
      level: :error,
      fingerprint: ['mask_job_stranded_lock', attachment.id.to_s],
      extra: {
        attachment_id: attachment.id,
        lock_key: lock_key,
        remaining_ttl_ms: remaining_ttl_ms,
        lock_deleted: true
      }
    )
  end
end
