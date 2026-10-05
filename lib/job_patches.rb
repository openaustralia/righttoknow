# frozen_string_literal: true

# Add a callback - to be executed before each request in development,
# and at startup in production - to patch existing app classes.
# See http://stackoverflow.com/questions/7072758/plugin-not-reloading-in-development-mode
#
Rails.configuration.to_prepare do
  FoiAttachmentMaskJob.class_eval do
    # `unique` replaces lock_options wholesale, so the host's `on_conflict: :log`
    # has to be repeated here. The enqueue-side lock_ttl is deliberately left
    # at the gem default (a day): an enqueued job can legitimately wait hours
    # in a backed-up queue. Only the runtime lock, which a hard death mid-job
    # leaves behind, is capped. See
    # doc/adr/0005-sidekiq-runs-without-a-systemd-watchdog.md (#1115).
    unique :until_and_while_executing,
           on_conflict: :log,
           on_runtime_conflict: MaskJobRuntimeConflict,
           runtime_lock_ttl: 30.minutes
  end
end
