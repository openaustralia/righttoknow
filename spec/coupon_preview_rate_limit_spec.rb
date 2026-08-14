# frozen_string_literal: true

# Throttling for the theme's coupon preview endpoint.
#
# The endpoint reports valid / invalid / expired per request and calls Stripe
# each time, so without a limit it enumerates the coupon namespace cheaply and
# amplifies against Stripe's rate limit. Limiting is per user rather than per IP
# because the action requires a login, and an IP key would penalise everyone
# behind a shared address.
#
# The limiter is stubbed rather than exercised for real: it is PStore backed and
# spec_helper only cleans up the signup limiter, so a real one would leave state
# behind between examples and could make this order-dependent.
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
  let(:user) { FactoryBot.create(:user) }
  let(:limiter) { double(AlaveteliRateLimiter::RateLimiter) }

  let!(:pro_price) do
    stripe_helper.create_price(
      id: 'pro', product: product.id, unit_amount: 4500
    )
  end

  def json
    JSON.parse(response.body)
  end

  before do
    allow(AlaveteliConfiguration).to receive(:stripe_tax_rate).and_return('0.10')
    allow(AlaveteliConfiguration).to receive(:iso_currency_code)
      .and_return('GBP')
    sign_in user
    allow(controller).to receive(:coupon_preview_rate_limiter)
      .and_return(limiter)
    allow(limiter).to receive(:record!)
  end

  describe 'GET #coupon_preview' do
    context 'when the user is under the limit' do
      before do
        allow(limiter).to receive(:limit?).and_return(false)
        get :coupon_preview, params: { price_id: 'pro', coupon_code: 'NOPE' }
      end

      it 'answers normally' do
        expect(response).to have_http_status(:ok)
        expect(json['status']).to eq('invalid')
      end

      it 'counts the attempt against the user' do
        expect(limiter).to have_received(:record!).with(user.id)
      end
    end

    context 'when the user is over the limit' do
      before do
        allow(limiter).to receive(:limit?).and_return(true)
        get :coupon_preview, params: { price_id: 'pro', coupon_code: 'NOPE' }
      end

      it 'refuses with 429 and a parseable body' do
        expect(response).to have_http_status(:too_many_requests)
        expect(json['status']).to eq('error')
        expect(json['message']).to be_present
      end

      it 'does not reveal whether the code exists' do
        expect(json).not_to have_key('amount')
        expect(json['status']).not_to eq('invalid')
      end
    end

    # A typed code is looked up as a coupon and then as a promotion code, so
    # the endpoint is an existence oracle over both namespaces. Promotion codes
    # are not namespaced, which makes them the easier of the two to guess. The
    # limiter has to short circuit before either lookup, otherwise a throttled
    # user still learns what exists and still amplifies against Stripe.
    context 'when the user is over the limit' do
      before do
        allow(limiter).to receive(:limit?).and_return(true)
        allow(Stripe::Coupon).to receive(:retrieve).and_call_original
        allow(Stripe::PromotionCode).to receive(:list).and_call_original
        get :coupon_preview, params: { price_id: 'pro', coupon_code: 'SUMMER25' }
      end

      it 'does not look the code up in either namespace' do
        expect(Stripe::Coupon).not_to have_received(:retrieve)
        expect(Stripe::PromotionCode).not_to have_received(:list)
      end
    end

    # The field is cleared and retyped in ordinary use, and a blank code is
    # answered from the price alone without touching Stripe, so it must not
    # consume the allowance.
    context 'with a blank coupon code' do
      before do
        allow(limiter).to receive(:limit?).and_return(false)
        get :coupon_preview, params: { price_id: 'pro', coupon_code: '' }
      end

      it 'does not count against the limit' do
        expect(limiter).not_to have_received(:record!)
      end
    end
  end
end
