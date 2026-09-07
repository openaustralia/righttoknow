# frozen_string_literal: true

# The form object behind the external review application flow (issue #1107):
# validations for the structured questions, composition of the public
# application letter, and the private (never published) contact details.
# The flow itself is covered in external_review_flow_spec.rb.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)

RSpec.describe ExternalReviewApplication do
  let(:public_body) do
    FactoryBot.create(:public_body,
                      name: 'Department of Examples',
                      tag_string: 'federal')
  end
  let(:info_request) do
    FactoryBot.create(:info_request,
                      title: 'Ministerial diaries',
                      public_body: public_body)
  end

  def application(attributes = {})
    described_class.new({
      info_request: info_request,
      decision_type: 'original',
      decision_date: '2026-08-01',
      disagreement: 'The section 47E exemption was wrongly applied.',
      phone: '0491 570 006',
      oaic_reference: '',
      assistance: ''
    }.merge(attributes))
  end

  describe 'validations' do
    it 'is valid with the required answers' do
      expect(application).to be_valid
    end

    it 'requires a decision type' do
      expect(application(decision_type: nil)).not_to be_valid
    end

    it 'rejects unknown decision types' do
      expect(application(decision_type: 'made_up')).not_to be_valid
    end

    it 'requires an explanation of the disagreement' do
      expect(application(disagreement: '')).not_to be_valid
    end

    it 'requires a contact telephone number' do
      expect(application(phone: '')).not_to be_valid
    end

    it 'requires a parseable decision date' do
      expect(application(decision_date: '')).not_to be_valid
      expect(application(decision_date: 'not a date')).not_to be_valid
    end

    it 'does not require a decision date for a deemed refusal' do
      expect(application(decision_type: 'no_decision', decision_date: ''))
        .to be_valid
    end
  end

  describe '#outside_time_limit?' do
    it 'is false within 60 days of the decision' do
      app = application(decision_date: 59.days.ago.to_date.iso8601)
      expect(app.outside_time_limit?).to be false
    end

    it 'is true more than 60 days after the decision' do
      app = application(decision_date: 61.days.ago.to_date.iso8601)
      expect(app.outside_time_limit?).to be true
    end

    it 'is false for a deemed refusal, which has no time limit' do
      app = application(decision_type: 'no_decision',
                        decision_date: 61.days.ago.to_date.iso8601)
      expect(app.outside_time_limit?).to be false
    end
  end

  describe '#letter_body' do
    it 'addresses the jurisdiction reviewer and includes the particulars' do
      body = application.letter_body

      expect(body).to start_with(
        'Dear Office of the Australian Information Commissioner,'
      )
      expect(body).to include("Department of Examples's original decision")
      expect(body).to include('1 August 2026')
      expect(body).to include('The section 47E exemption was wrongly applied.')
      expect(body).to include(info_request.url_title)
      expect(body).to end_with("Yours faithfully,\n\n#{info_request.user_name}")
    end

    it 'describes an internal review decision when that is under review' do
      body = application(decision_type: 'internal_review').letter_body
      expect(body).to include('internal review decision')
    end

    it 'describes a deemed refusal when no decision was received' do
      body = application(decision_type: 'no_decision',
                         decision_date: '').letter_body
      expect(body).to include('deemed refusal')
      expect(body).not_to include('I was notified on')
    end

    it 'never contains the private contact details' do
      body = application(oaic_reference: 'MR26/00001',
                         assistance: 'Auslan interpreter').letter_body
      expect(body).not_to include('0491 570 006')
      expect(body).not_to include('MR26/00001')
      expect(body).not_to include('Auslan interpreter')
    end
  end

  describe '#private_details' do
    it 'includes the phone number and any optional answers, stripped' do
      details = application(oaic_reference: ' MR26/00001 ',
                            assistance: 'Auslan interpreter').private_details
      expect(details).to eq(phone: '0491 570 006',
                            oaic_reference: 'MR26/00001',
                            assistance: 'Auslan interpreter')
    end

    it 'omits blank optional answers' do
      expect(application.private_details).to eq(phone: '0491 570 006')
    end
  end
end
