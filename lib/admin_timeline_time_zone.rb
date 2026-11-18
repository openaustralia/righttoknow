# frozen_string_literal: true

# The admin timeline selects each event's time as a raw SQL alias
# (`created_at AS timestamp`), so Rails hands it back as a UTC Time instead of
# converting it to the app time zone. The view then mixes zones: the date
# heading converts it (simple_date calls in_time_zone), but the time of day and
# the weekday print the UTC value. An event at 08:00 Wednesday in Sydney showed
# as "November 18 Tuesday" with a time of 21:00:00.
#
# This is a general Alaveteli bug, introduced upstream in c71395e39. Delete this
# module once a fix is released by mysociety/alaveteli.
module AdminTimelineTimeZone
  private

  def get_timeline_events(pager)
    events, count = super
    [events.map { |record, timestamp| [record, timestamp.in_time_zone] }, count]
  end
end
