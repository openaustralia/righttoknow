# frozen_string_literal: true

# The external review application flow for federal authorities (issue #1107):
# a structured form at /request/:url_title/followups/new?external_review=1
# that composes and emails an Information Commissioner review application to
# the OAIC, keeps the contact details out of the public record, and moves the
# request into the theme's external_review state. See
# lib/controller_patches.rb (ExternalReviewFollowups), lib/model_patches.rb
# (ExternalReviewOutgoingMessage) and lib/customstates.rb.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)

RSpec.describe FollowupsController, type: :controller do # rubocop:disable Metrics/BlockLength
  render_views

  let(:user) { FactoryBot.create(:user) }
  let(:public_body) do
    FactoryBot.create(:public_body,
                      name: 'Department of Examples',
                      tag_string: 'federal')
  end
  let(:info_request) do
    FactoryBot.create(:info_request, public_body: public_body, user: user)
  end

  # 0491 570 006 is one of ACMA's numbers reserved for fictional use.
  let(:valid_fields) do
    {
      decision_type: 'original',
      decision_date: 70.days.ago.to_date.iso8601,
      disagreement: 'The section 47E exemption was wrongly applied to my request.',
      phone: '0491 570 006',
      oaic_reference: 'MR26/00001',
      assistance: 'Please use email where possible'
    }
  end

  before { sign_in user }

  describe 'GET #new with external_review=1' do
    it 'renders the structured application form for a federal request' do
      get :new, params: { request_url_title: info_request.url_title,
                          external_review: '1' }

      expect(response).to render_template('followups/external_review_new')
      expect(response.body)
        .to include('Office of the Australian Information Commissioner')
      expect(response.body).to include('will <strong>not</strong> be published')
    end

    it 'is not found for a jurisdiction without a wired-up reviewer' do
      nsw_body = FactoryBot.create(:public_body, tag_string: 'NSW')
      nsw_request = FactoryBot.create(:info_request,
                                      public_body: nsw_body, user: user)

      expect do
        get :new, params: { request_url_title: nsw_request.url_title,
                            external_review: '1' }
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'POST #preview with external_review=1' do
    def post_preview(fields = valid_fields)
      post :preview, params: { request_url_title: info_request.url_title,
                               external_review: '1',
                               external_review_application: fields }
    end

    it 'shows the composed letter, read-only, addressed to the reviewer' do
      post_preview

      expect(response).to render_template('followups/external_review_preview')
      expect(response.body)
        .to include('Office of the Australian Information Commissioner')
      expect(response.body).to include('Information Commissioner review ' \
                                       'application')
      expect(response.body)
        .to include('The section 47E exemption was wrongly applied')
      # The letter is composed, not edited: no message body field.
      expect(response.body).not_to include('outgoing_message[body]')
    end

    it 'keeps the contact details out of the letter itself' do
      post_preview

      expect(assigns(:outgoing_message).body).not_to include('0491 570 006')
      expect(assigns(:outgoing_message).body).not_to include('MR26/00001')
      expect(response.body)
        .to include('Sent to the reviewer but not published')
    end

    it 're-renders the form when required answers are missing' do
      post_preview(valid_fields.merge(disagreement: '', phone: ''))

      expect(response).to render_template('followups/external_review_new')
      expect(response.body)
        .to include('Please explain which parts of the decision you disagree')
      expect(response.body)
        .to include('Please enter a contact telephone number')
    end

    it 'warns, without blocking, when outside the 60 day time limit' do
      post_preview

      expect(response).to render_template('followups/external_review_preview')
      expect(response.body).to include('extension of time')
    end

    it 'does not warn about the time limit for a deemed refusal' do
      post_preview(valid_fields.merge(decision_type: 'no_decision',
                                      decision_date: ''))

      expect(response.body).not_to include('extension of time')
    end
  end

  describe 'POST #create with external_review=1' do
    def post_create(fields = valid_fields, extra = {})
      post :create, params: { request_url_title: info_request.url_title,
                              external_review: '1',
                              external_review_application: fields }.merge(extra)
    end

    it 'emails the application to the reviewer, appendix included' do
      expect { post_create }
        .to change { ActionMailer::Base.deliveries.size }.by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq(['FOIDR@oaic.gov.au'])
      expect(mail.subject)
        .to include('Information Commissioner review application')
      expect(mail.subject).to include('Department of Examples')
      expect(mail.body.to_s)
        .to include('not published on Right to Know')
      expect(mail.body.to_s).to include('0491 570 006')
      expect(mail.body.to_s).to include('MR26/00001')
      expect(mail.body.to_s).to include('Please use email where possible')
      expect(mail.body.to_s).to include(info_request.incoming_email)
    end

    it 'keeps the private details out of the public message' do
      post_create

      outgoing_message = info_request.reload.outgoing_messages.last
      expect(outgoing_message.what_doing).to eq('external_review')
      expect(outgoing_message.body).not_to include('0491 570 006')
      expect(outgoing_message.body).not_to include('MR26/00001')
      expect(outgoing_message.body)
        .to include('The section 47E exemption was wrongly applied')
    end

    it 'moves the request into the external_review state' do
      post_create

      expect(info_request.reload.described_state).to eq('external_review')
      expect(InfoRequest.get_status_description('external_review'))
        .to eq('Awaiting external review')
      expect(response).to redirect_to(request_url(info_request))
      expect(flash[:notice]).to include('has been sent')
    end

    it 'records the private details in the followup_sent event for admins' do
      post_create

      event = info_request.reload.info_request_events
                          .where(event_type: 'followup_sent').last
      details = event.params[:external_review_application]
      expect(details[:phone]).to eq('0491 570 006')
      expect(details[:oaic_reference]).to eq('MR26/00001')
      expect(details[:assistance]).to eq('Please use email where possible')
    end

    it 'still records the private details for admins when sending fails' do
      # Reaching into the mailer: there is no way to make real delivery
      # raise one of OutgoingMessage.expected_send_errors from a controller
      # spec, and the point here is what we persist when it does.
      allow(OutgoingMailer).to receive(:followup).and_raise(IOError)

      post_create

      event = info_request.reload.info_request_events
                          .where(event_type: 'send_error').last
      expect(event.params[:external_review_application][:phone])
        .to eq('0491 570 006')
      expect(flash[:error]).to include('not yet sent')
    end

    it 'adds a censor rule so the phone number is redacted if quoted back' do
      post_create

      rule = info_request.reload.censor_rules.find_by(text: '0491 570 006')
      expect(rule).to be_present
      expect(rule.replacement).to eq('[phone number]')
      expect(rule.last_edit_editor).to eq('system')
      expect(rule.apply_to_text('Call me on 0491 570 006 today'))
        .to eq('Call me on [phone number] today')
    end

    it 'does not duplicate the censor rule on a repeat application' do
      post_create
      post_create(valid_fields.merge(disagreement: 'A different explanation ' \
                                                   'of the disagreement.'))

      expect(
        info_request.reload.censor_rules.where(text: '0491 570 006').count
      ).to eq(1)
    end

    it 'rejects sending the exact same application twice' do
      post_create

      expect { post_create }
        .not_to(change { ActionMailer::Base.deliveries.size })
      expect(flash[:error]).to include('previously submitted')
      expect(response).to render_template('followups/external_review_new')
    end

    it 'returns to the form for re-editing from the preview' do
      post_create(valid_fields, reedit: '1')

      expect(response).to render_template('followups/external_review_new')
      expect(response.body).to include(valid_fields[:disagreement])
    end

    it 'sends nothing when required answers are missing' do
      expect { post_create(valid_fields.merge(phone: '')) }
        .not_to(change { ActionMailer::Base.deliveries.size })
      expect(response).to render_template('followups/external_review_new')
    end
  end
end

RSpec.describe RequestController, type: :controller do
  render_views

  let(:user) { FactoryBot.create(:user) }
  let(:public_body) do
    FactoryBot.create(:public_body,
                      name: 'Department of Examples',
                      tag_string: 'federal')
  end
  let(:info_request) do
    FactoryBot.create(:info_request, public_body: public_body, user: user)
  end

  describe 'the request page for a federal request' do
    it 'offers "Apply for external review" in the actions menu' do
      get :show, params: { url_title: info_request.url_title }

      expect(response.body).to include('Apply for external review')
      expect(response.body)
        .to include('followups/new?external_review=1')
    end

    it 'does not offer external review for other jurisdictions' do
      nsw_body = FactoryBot.create(:public_body, tag_string: 'NSW')
      nsw_request = FactoryBot.create(:info_request, public_body: nsw_body)

      get :show, params: { url_title: nsw_request.url_title }

      expect(response.body).not_to include('Apply for external review')
    end

    it 'shows the awaiting external review banner once in the state' do
      info_request.set_described_state('external_review')

      get :show, params: { url_title: info_request.url_title }

      expect(response.body)
        .to include('awaiting external review')
      expect(response.body)
        .to include('Office of the Australian Information Commissioner')
    end

    it 'points long-overdue federal requests at external review, not ' \
       'internal review' do
      info_request

      travel_to(1.year.from_now) do
        get :show, params: { url_title: info_request.url_title }
      end

      expect(response.body).to include('review of the deemed refusal')
      expect(response.body).to include('external_review=1')
      expect(response.body).not_to include('requesting an internal review')
    end

    it 'keeps the internal review advice for long-overdue non-federal ' \
       'requests' do
      nsw_body = FactoryBot.create(:public_body, tag_string: 'NSW')
      nsw_request = FactoryBot.create(:info_request, public_body: nsw_body)

      travel_to(1.year.from_now) do
        get :show, params: { url_title: nsw_request.url_title }
      end

      expect(response.body).to include('requesting an internal review')
    end
  end
end
