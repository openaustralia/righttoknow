# frozen_string_literal: true

# Guards the login gate on AlaveteliPro::PlansController#show against theme
# patches clobbering the host's callbacks. Re-registering a host callback by
# name in lib/controller_patches.rb (e.g. `before_action :authenticate`)
# replaces the host's registration instead of adding to it, which removed
# authentication from #show entirely and 500ed every logged-out visitor in
# check_has_current_subscription (issue #1055).
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)
require 'stripe_mock'

RSpec.describe AlaveteliPro::PlansController, type: :controller do
  before { StripeMock.start }
  after { StripeMock.stop }

  let(:stripe_helper) { StripeMock.create_test_helper }
  let(:product) { stripe_helper.create_product }

  let!(:pro_price) do
    stripe_helper.create_price(
      id: 'pro', product: product.id, unit_amount: 4500
    )
  end

  describe 'GET #show' do
    context 'without a signed-in user' do
      before { get :show, params: { id: 'pro' } }

      it 'redirects to the login form with a post redirect back to the plan' do
        expect(response).to redirect_to(signin_path(token: PostRedirect.last.token))
        expect(PostRedirect.last.uri).to eq(plan_path('pro'))
      end
    end

    context 'with a signed-in user without a subscription' do
      before do
        sign_in FactoryBot.create(:user)
        get :show, params: { id: 'pro' }
      end

      it 'renders the plan page' do
        expect(response).to be_successful
      end
    end
  end
end
