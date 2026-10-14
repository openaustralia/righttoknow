# frozen_string_literal: true

# ExternalReviewSender is the one send path for external review applications,
# used by FollowupsController and by script/seed_test_data.rb. The controller
# flow (form, preview, flash) is covered in external_review_flow_spec.rb; this
# checks the sender's own contract, since the seed script calls it directly.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)

RSpec.describe ExternalReviewSender do
  let(:public_body) do
    FactoryBot.create(:public_body,
                      name: 'Department of Examples',
                      tag_string: 'federal')
  end
  let(:info_request) do
    FactoryBot.create(:info_request, public_body: public_body)
  end
  # 0491 570 006 is one of ACMA's numbers reserved for fictional use.
  let(:application) do
    ExternalReviewApplication.new(
      info_request: info_request,
      decision_type: 'original',
      decision_date: 10.days.ago.to_date.iso8601,
      disagreement: 'The section 47E exemption was wrongly applied.',
      phone: '0491 570 006'
    )
  end
  let(:outgoing_message) do
    described_class.build_outgoing_message(application)
  end
  let(:sender) { described_class.new(application, outgoing_message) }

  describe '.build_outgoing_message' do
    it 'builds an unsaved external_review followup carrying the appendix' do
      expect(outgoing_message).to be_new_record
      expect(outgoing_message.what_doing).to eq('external_review')
      expect(outgoing_message.message_type).to eq('followup')
      expect(outgoing_message.body).to include('section 47E')
      expect(outgoing_message.body).not_to include('0491 570 006')
      expect(outgoing_message.external_review_details[:phone])
        .to eq('0491 570 006')
    end
  end

  describe '#deliver' do
    it 'sends to the reviewer and leaves the request awaiting external review' do
      expect(sender.deliver).to be(true)

      expect(ActionMailer::Base.deliveries.last.to).to eq(['FOIDR@oaic.gov.au'])
      expect(outgoing_message.reload.status).to eq('sent')
      expect(info_request.reload.described_state).to eq('external_review')
      expect(info_request.censor_rules.find_by(text: '0491 570 006'))
        .to be_present
      event = info_request.info_request_events
                          .where(event_type: 'followup_sent').last
      expect(event.params[:external_review_application][:phone])
        .to eq('0491 570 006')
    end

    it 'returns false and records a send_error when delivery fails' do
      # No way to make real delivery raise an expected send error here; the
      # contract under test is what the sender reports and persists when it
      # does.
      allow(OutgoingMailer).to receive(:followup).and_raise(IOError)

      expect(sender.deliver).to be(false)

      expect(outgoing_message.reload.status).to eq('failed')
      expect(info_request.reload.described_state).not_to eq('external_review')
      event = info_request.info_request_events
                          .where(event_type: 'send_error').last
      expect(event.params[:external_review_application][:phone])
        .to eq('0491 570 006')
    end
  end
end
