# frozen_string_literal: true

# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper'))

# The theme keeps the host's denormalised date_response_required_by column
# jurisdiction-correct (via its calculate_date_response_required_by override)
# and trusts it when reading (see lib/model_patches.rb). These specs guard
# both halves: what gets stored when a request is sent, and that the reader
# prefers the stored value over recomputing.
RSpec.describe InfoRequest, 'jurisdiction-aware due dates' do
  def create_request_to_body_tagged(tag)
    public_body = FactoryBot.create(:public_body, tag_string: tag)
    FactoryBot.create(:info_request, public_body: public_body)
  end

  describe 'the stored date_response_required_by column' do
    it 'is stored using working days for a NSW authority when the request is sent' do
      info_request = create_request_to_body_tagged('NSW')

      expected = Holiday.due_date_from(
        info_request.date_initial_request_last_sent_at, 20, 'working'
      )
      expect(info_request.read_attribute(:date_response_required_by)).to eq(expected)
    end

    it 'is stored using calendar days for a federal authority when the request is sent' do
      info_request = create_request_to_body_tagged('federal')

      expected = Holiday.due_date_from(
        info_request.date_initial_request_last_sent_at, 30, 'calendar'
      )
      expect(info_request.read_attribute(:date_response_required_by)).to eq(expected)
    end
  end

  describe '#date_response_required_by' do
    it 'prefers the stored column over recomputing' do
      info_request = create_request_to_body_tagged('NSW')
      # A date no computation from this request's sent date could produce, so
      # getting it back proves the stored value was used.
      info_request.update_columns(date_response_required_by: Date.new(2050, 1, 4))

      expect(info_request.reload.date_response_required_by).to eq(Date.new(2050, 1, 4))
    end

    it 'falls back to a jurisdiction-aware calculation when the column is empty' do
      info_request = create_request_to_body_tagged('NSW')
      info_request.update_columns(date_response_required_by: nil)
      info_request.reload

      expected = Holiday.due_date_from(
        info_request.date_initial_request_last_sent_at, 20, 'working'
      )
      expect(info_request.date_response_required_by).to eq(expected)
    end
  end
end
