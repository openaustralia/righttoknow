# Sidekiq runs without a systemd watchdog

Right To Know's Sidekiq unit
([`roles/internal/righttoknow/templates/sidekiq.service.j2`](https://github.com/openaustralia/infrastructure/blob/main/roles/internal/righttoknow/templates/sidekiq.service.j2)
in the `infrastructure` repo) had `Type=notify` with `WatchdogSec=10`, as
Sidekiq's own example unit ships. On 15 September 2026 systemd sent the
service `SIGABRT` twice, each time while `pdftk` children were alive, and each
abort left a `FoiAttachmentMaskJob` runtime lock stranded in Redis for its
default day-long TTL. Three attachments then sat on "Attachment processing..."
with every re-enqueued job aborting in silence (#1115). That pattern is
consistent with the watchdog: the `Watchdog timeout (limit 10s)!` journal line
that would confirm it has not yet been read.

A systemd watchdog only detects "alive but not scheduling threads". For this
workload that is either a host stall or a Ruby process holding the GVL for
more than ten seconds, which masking a large uncompressed PDF in-process does
by design. Aborting the process mid-job with `SIGABRT` skips the `ensure` in
`activejob-uniqueness`'s `around_perform` that releases the runtime lock, so
the watchdog turned a slow job into a silent day-long outage for that
attachment and then restarted Sidekiq to do it again.

- **`WatchdogSec` is removed and stays removed.** `Type=notify` is kept so
  systemd's READY ordering still works. A crashed process is covered by
  `Restart=always`, and jobs that no worker will ever drain are caught by the
  hourly `check-orphaned-sidekiq-queues` cron (`script/check_orphaned_queues.rb`,
  wrapped in a Sentry cron monitor). Do not put `WatchdogSec` back because the
  example unit has it; the example assumes short jobs.
- **The theme caps the runtime lock at 30 minutes** (`lib/job_patches.rb`).
  This is the damage cap for any other hard death: OOM kill, `SIGKILL` on a
  stop timeout, a host reboot. The enqueue-side lock keeps the gem default of
  a day, because a queued job can legitimately wait hours in a backed-up
  queue and shortening it would let duplicates enqueue.
- **Stranded locks are detected and cleared** (`lib/mask_job_runtime_conflict.rb`).
  On a runtime conflict, a lock older than 60 s with no in-flight
  `FoiAttachmentMaskJob` for that attachment in `Sidekiq::Workers` is stranded:
  it is reported to Sentry (fingerprinted per attachment) and deleted, so the
  wait page's next poll enqueues a job that acquires it. The 60 s guard covers
  the heartbeat lag before a just-started job appears in `Sidekiq::Workers`.
  A misclassification costs one duplicate mask run of the same attachment;
  the alternative was a 30 minute outage, so the trade is accepted.

#1083 covers separate memory trouble on the same host and is not the cause
here; no OOM killer activity appears in the journal around these aborts. If it
ever is, the 30 minute cap and stranded-lock detection are what limit the
damage.

_Decided 2026-09-15._
