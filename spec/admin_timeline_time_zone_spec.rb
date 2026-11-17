# frozen_string_literal: true

# The admin timeline reads event times from a raw SQL alias, which Rails returns
# in UTC. See lib/admin_timeline_time_zone.rb.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)

RSpec.describe AdminGeneralController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers

  render_views

  # 21:00:38 UTC on Tuesday is 08:00:38 on Wednesday in Sydney (AEDT, UTC+11)
  let(:event_time) { Time.utc(2026, 11, 17, 21, 0, 38) }

  before do
    basic_auth_login(@request)
    info_request = FactoryBot.create(:info_request)
    @event = info_request.log_event('edit', {})
    @event.update_columns(created_at: event_time)
  end

  around do |example|
    Time.use_zone('Australia/Sydney') do
      travel_to(event_time + 1.hour) { example.run }
    end
  end

  %w[info_request_event all].each do |event_type|
    context "with event_type #{event_type}" do
      before { get :timeline, params: { event_type: event_type } }

      it 'converts event times to the app time zone' do
        timestamp = assigns[:events].find { |record, _| record == @event }.last
        expect(timestamp.utc_offset).to eq(11.hours)
        expect(timestamp).to eq(event_time)
      end

      it 'shows the local time and weekday together' do
        expect(response.body).to include('08:00:38')
        expect(response.body).to include('Wednesday')
        expect(response.body).not_to include('21:00:38')
      end
    end
  end
end
