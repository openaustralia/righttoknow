# frozen_string_literal: true

# Guards the "are you asking for personal information?" gate on the new request
# form (issue #1065).
#
# The gate hides the rest of the form until the question is answered. It used to
# be applied by personal_message_toggler.js, which needed jQuery from the main
# application.js bundle; when that bundle failed to load the gate didn't
# degrade, it disappeared, and people could submit without ever seeing the
# warning (Sentry RIGHT-TO-KNOW-JS-4). It's now CSS plus the server-rendered
# `checked` asserted here, so it doesn't depend on JavaScript at all.
#
# Only the part with logic in it is tested: whether "No" is pre-selected for
# someone who has already been through the form once, so a validation error or
# duplicate warning doesn't lose their place. The hiding itself is CSS
# (app/assets/stylesheets/responsive/rtk/_request_personal_message.scss) and
# isn't reachable from a controller spec.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)

RSpec.describe RequestController, type: :controller do
  render_views

  let(:public_body) { FactoryBot.create(:public_body) }

  # The gate only renders for authorities with two or more hidden requests
  # (PublicBody#info_requests_hidden_count, added in lib/model_patches.rb).
  before { FactoryBot.create_list(:info_request, 2, :hidden, public_body: public_body) }

  describe 'GET #new' do
    context 'when starting a fresh request' do
      before { get :new, params: { public_body_id: public_body.id } }

      it 'asks the personal information question' do
        expect(response.body)
          .to have_css('#request_personal_switch', visible: :all)
      end

      it 'leaves "No" unselected, so the gate hides the rest of the form' do
        expect(response.body)
          .not_to have_css('#request_personal_switch_no[checked]', visible: :all)
      end
    end

    context 'when the same request has already been made' do
      let!(:existing_request) do
        FactoryBot.create(:info_request, public_body: public_body)
      end

      before do
        get :new, params: {
          submitted_new_request: 1,
          info_request: {
            title: existing_request.title,
            public_body_id: public_body.id
          },
          outgoing_message: {
            body: existing_request.outgoing_messages.first.body
          }
        }
      end

      it 'warns that the request already exists' do
        expect(response.body).to have_css('.errorExplanation', visible: :all)
      end

      it 'answers "No" so the person keeps their place' do
        expect(response.body)
          .to have_css('#request_personal_switch_no[checked]', visible: :all)
      end
    end

    context 'when a submission comes back with a validation error' do
      # The regression this guards: the blank title means neither
      # @existing_request nor @info_request.title says the form has been
      # through once, but foi_error_messages_for has rendered
      # .errorExplanation, which is what the old JavaScript keyed off.
      before do
        get :new, params: {
          submitted_new_request: 1,
          info_request: { title: '', public_body_id: public_body.id },
          outgoing_message: { body: 'Please send me the minutes.' }
        }
      end

      it 'shows the validation error' do
        expect(response.body).to have_css('.errorExplanation', visible: :all)
      end

      it 'answers "No" so the person keeps their place' do
        expect(response.body)
          .to have_css('#request_personal_switch_no[checked]', visible: :all)
      end
    end

    context 'when coming back to a request that has a subject already' do
      before do
        get :new, params: {
          submitted_new_request: 1,
          info_request: {
            title: 'Minutes of the November board meeting',
            public_body_id: public_body.id
          },
          outgoing_message: { body: '' }
        }
      end

      it 'answers "No" so the person keeps their place' do
        expect(response.body)
          .to have_css('#request_personal_switch_no[checked]', visible: :all)
      end
    end
  end

  describe 'GET #new for an authority with fewer than two hidden requests' do
    let(:quiet_body) { FactoryBot.create(:public_body) }

    before { get :new, params: { public_body_id: quiet_body.id } }

    it 'does not ask the personal information question at all' do
      expect(response.body)
        .not_to have_css('#request_personal_switch', visible: :all)
    end
  end
end
