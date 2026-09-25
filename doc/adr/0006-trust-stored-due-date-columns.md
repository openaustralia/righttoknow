# Trust the stored due-date columns, kept jurisdiction-correct

Alaveteli denormalises each request's response deadlines into columns on
`info_requests` (`date_response_required_by`, `date_very_overdue_after`,
`date_initial_request_last_sent_at`, `last_event_forming_initial_request_id`),
populated whenever an event resets the due dates, so that
`InfoRequest#calculate_status` is a couple of attribute reads. This theme's
`InfoRequest#date_response_required_by` override predated those columns (2015
vs 2016) and always recomputed the deadline from the public body's
jurisdiction tag — per request: tag lookups, working-day/holiday maths, and
for pre-2016 requests a full walk of the request's event history. That made
any page showing many statuses unusably slow, and in August 2025 the request
status had to be hidden from `/list` entirely.

The theme now matches the host's caching instead (`lib/model_patches.rb`):

- **`calculate_date_response_required_by` is the override point**, not the
  reader. The host calls it when storing the columns, so stored values are
  jurisdiction-aware from now on.
- **The reader prefers the stored column**, computing only as a fallback,
  exactly like the host's own reader.
- **`script/populate_due_dates.rb` backfills history** — values stored before
  this change used the site-wide config (wrong for most jurisdictions), and
  pre-2016 requests had no stored values at all. It must be run once on each
  deployed environment; it is idempotent.

The consequence to remember: stored deadlines are snapshots. **If a public
body's jurisdiction tag is ever changed, re-run the backfill script** (or at
least for that body's requests) — nothing recomputes them automatically.

`date_very_overdue_after` ("long overdue") stays as the host computes it, from
the site-wide config; the theme has never made it jurisdiction-aware, and
changing that was out of scope here.

_Decided 2026-09-11._
