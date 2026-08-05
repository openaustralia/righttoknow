# frozen_string_literal: true

# Exercises the theme's checkout-side enforcement of coupon `interval` metadata
# restrictions, added to AlaveteliPro::SubscriptionsController in
# lib/controller_patches.rb.
#
# Stripe's coupon applies_to is product-scoped only, so it cannot stop a
# monthly-only coupon from discounting the annual price within the same product.
# The theme carries the restriction in coupon metadata (`interval`) and blocks
# the mismatch before a subscription is created.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)
require 'stripe_mock'

RSpec.describe AlaveteliPro::SubscriptionsController,
               type: :controller, feature: :pro_pricing do
  before { StripeMock.start }
  after { StripeMock.stop }

  let(:stripe_helper) { StripeMock.create_test_helper }
  let(:product) { stripe_helper.create_product }
  let(:token) { stripe_helper.generate_card_token }
  let(:user) { FactoryBot.create(:user) }

  # StripeMock defaults recurring.interval to "month".
  let!(:monthly_price) do
    stripe_helper.create_price(
      id: 'pro', product: product.id, unit_amount: 1000
    )
  end

  let!(:annual_price) do
    stripe_helper.create_price(
      id: 'annual_price', product: product.id, unit_amount: 10_000,
      recurring: { interval: 'year', interval_count: 1 }
    )
  end

  before do
    allow(AlaveteliConfiguration).to receive(:stripe_prices)
      .and_return('pro' => 'pro', 'annual_price' => 'annual')
    allow(AlaveteliConfiguration).to receive(:stripe_tax_rate).and_return('0.0')

    # Restricted to the monthly interval, like a monthly-only coupon.
    stripe_helper.create_coupon(
      id: 'MONTHLYONLY', percent_off: 50, amount_off: nil, currency: nil,
      metadata: { interval: 'month' }
    )

    sign_in user
  end

  describe 'POST #create with an interval-restricted coupon' do
    context 'on the matching (monthly) price' do
      before do
        post :create, params: {
          'stripe_token' => token,
          'price_id' => 'pro',
          'coupon_code' => 'MONTHLYONLY'
        }
      end

      it 'applies the coupon' do
        expect(assigns(:subscription).discount.coupon.id).to eq('MONTHLYONLY')
      end

      it 'subscribes the user' do
        expect(response).to redirect_to(
          authorise_subscription_path(assigns(:subscription).id)
        )
      end
    end

    context 'on a non-matching (annual) price' do
      before do
        post :create, params: {
          'stripe_token' => token,
          'price_id' => 'annual',
          'coupon_code' => 'MONTHLYONLY'
        }
      end

      it 'does not create a subscription' do
        expect(assigns(:subscription)).to be_nil
      end

      it 'redirects back to the plan with an error' do
        expect(flash[:error])
          .to eq('This coupon code cannot be used with this plan.')
        expect(response).to redirect_to(plan_path('annual'))
      end
    end
  end

  describe 'POST #create with an unrestricted coupon' do
    before do
      stripe_helper.create_coupon(
        id: 'ANYPLAN', percent_off: 10, amount_off: nil, currency: nil
      )
      post :create, params: {
        'stripe_token' => token,
        'price_id' => 'annual',
        'coupon_code' => 'ANYPLAN'
      }
    end

    it 'applies to any interval' do
      expect(assigns(:subscription).discount.coupon.id).to eq('ANYPLAN')
    end
  end
end
