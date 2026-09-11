# frozen_string_literal: true

# Backfill the denormalised due-date columns on info_requests with
# jurisdiction-aware values.
#
# Why: from 2015 to 2026 this theme overrode InfoRequest#date_response_required_by
# to always recompute the due date from the public body's jurisdiction tag,
# because the override predated the host's denormalised due-date columns
# (Alaveteli 0.25, 2016). That left the stored columns populated with the
# host's site-wide-config values (wrong for most jurisdictions) or, for
# requests from before 2016, not populated at all. The theme now trusts the
# stored column (see lib/model_patches.rb), so this script makes the stored
# values correct:
#
#   * date_response_required_by is recomputed for every request using the
#     jurisdiction-aware logic (the same values the site displayed while the
#     always-recompute override was in place).
#   * last_event_forming_initial_request_id, date_initial_request_last_sent_at
#     and date_very_overdue_after are filled in only where NULL, using the
#     host's own fallback calculations - so pre-2016 requests stop walking
#     their whole event history on every status calculation.
#
# Writes use update_columns: no validations, callbacks, timestamps or search
# reindexing (none of these columns is indexed or user-visible history).
#
# Safe to re-run; it is idempotent. Re-run it (or at least the requests of the
# affected body) if a public body's jurisdiction tag is ever changed.
#
# ---------------------------------------------------------------------------
# Run from the Alaveteli app root:
#
#   bundle exec rails runner lib/themes/righttoknow/script/populate_due_dates.rb
# ---------------------------------------------------------------------------

scanned = 0
updated = 0
errors = 0

InfoRequest.find_each do |info_request|
  scanned += 1
  changes = {}

  # Assign (not save) the missing prerequisites first, so the date
  # calculations below read them from the attribute instead of re-walking the
  # request's event history; update_columns persists them at the end.
  if info_request.read_attribute(:last_event_forming_initial_request_id).nil?
    last_sent = info_request.calculate_last_event_forming_initial_request
    if last_sent
      info_request[:last_event_forming_initial_request_id] = last_sent.id
      changes[:last_event_forming_initial_request_id] = last_sent.id
    end
  end

  if info_request.read_attribute(:date_initial_request_last_sent_at).nil?
    date_last_sent = info_request.calculate_date_initial_request_last_sent_at
    info_request[:date_initial_request_last_sent_at] = date_last_sent
    changes[:date_initial_request_last_sent_at] = date_last_sent
  end

  # Jurisdiction-aware (theme override of calculate_date_response_required_by);
  # recomputed unconditionally because existing stored values were computed
  # with the site-wide config instead.
  stored_required_by = info_request.read_attribute(:date_response_required_by)
  required_by = info_request.calculate_date_response_required_by
  changes[:date_response_required_by] = required_by if stored_required_by != required_by

  very_overdue_missing = info_request.read_attribute(:date_very_overdue_after).nil?
  changes[:date_very_overdue_after] = info_request.calculate_date_very_overdue_after if very_overdue_missing

  unless changes.empty?
    info_request.update_columns(changes)
    updated += 1
  end
rescue StandardError => e
  errors += 1
  warn "populate_due_dates: info_request #{info_request.id}: #{e.class}: #{e.message}"
end

puts "populate_due_dates: scanned #{scanned}, updated #{updated}, errors #{errors}"
exit 1 if errors.positive?
