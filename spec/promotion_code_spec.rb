# frozen_string_literal: true

# Exercises the theme's support for Stripe promotion codes at Pro checkout,
# added in lib/models/alaveteli_pro/promotion_code.rb,
# lib/models/alaveteli_pro/discount_code_resolution.rb,
# lib/promotion_code_subscriptions.rb and wired up in
# lib/controller_patches.rb.
#
# Core resolves the typed code as a coupon id only, and writes whatever it
# finds under `coupon:`. The theme falls back to a promotion code lookup, and
# moves that id to Stripe's `promotion_code:` parameter so that Stripe applies
# the code, enforces its restrictions and counts the redemption.
#
# StripeMock caveats this file works around:
#
# - its promotion code list handler ignores the `code:` filter and returns
#   everything, so each example must have exactly one promotion code (it does
#   honour `active:`)
# - creating a subscription with `promotion_code:` is validated but no discount
#   is attached, so the seam is asserted against the params Stripe receives
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)
require 'stripe_mock'

RSpec.describe AlaveteliPro::SubscriptionsController, # rubocop:disable Metrics/BlockLength
               type: :controller, feature: :pro_pricing do
  before { StripeMock.start }
  after { StripeMock.stop }

  let(:stripe_helper) { StripeMock.create_test_helper }
  let(:product) { stripe_helper.create_product }
  let(:token) { stripe_helper.generate_card_token }
  let(:user) { FactoryBot.create(:user) }

  let!(:price) do
    stripe_helper.create_price(
      id: 'pro', product: product.id, unit_amount: 1000
    )
  end

  let!(:coupon) do
    stripe_helper.create_coupon(
      id: 'HALFOFF', percent_off: 50, amount_off: nil, currency: nil
    )
  end

  def create_promotion_code(attributes = {})
    Stripe::PromotionCode.create(
      { coupon: 'HALFOFF', code: 'SUMMER25' }.merge(attributes)
    )
  end

  def subscribe(coupon_code)
    post :create, params: {
      'stripe_token' => token,
      'price_id' => 'pro',
      'coupon_code' => coupon_code
    }
  end

  before do
    allow(AlaveteliConfiguration).to receive(:stripe_prices)
      .and_return('pro' => 'pro')
    allow(AlaveteliConfiguration).to receive(:stripe_tax_rate).and_return('0.0')

    sign_in user
  end

  describe 'POST #create with a promotion code' do
    let!(:promotion_code) { create_promotion_code }

    # The seam: core writes the id under `coupon:`, and
    # PromotionCodeSubscriptions has to move it. If this fails, people are
    # charged with the bare coupon applied and the promotion code's
    # times_redeemed never moves.
    it 'sends the promotion code to Stripe as a promotion code' do
      allow(Stripe::Subscription).to receive(:create).and_call_original

      subscribe('SUMMER25')

      expect(Stripe::Subscription).to have_received(:create).with(
        hash_including(promotion_code: promotion_code.id)
      )
      expect(Stripe::Subscription).not_to have_received(:create).with(
        hash_including(:coupon)
      )
    end

    it 'subscribes the user' do
      subscribe('SUMMER25')

      expect(response).to redirect_to(
        authorise_subscription_path(assigns(:subscription).id)
      )
    end
  end

  describe 'resolution order' do
    it 'resolves a promotion code when no coupon matches' do
      create_promotion_code

      subscribe('SUMMER25')

      expect(assigns(:coupon)).to be_a(AlaveteliPro::PromotionCode)
    end

    it 'prefers a coupon of the same name over a promotion code' do
      create_promotion_code(code: 'HALFOFF')

      subscribe('HALFOFF')

      expect(assigns(:coupon)).to be_a(AlaveteliPro::Coupon)
      expect(assigns(:coupon)).not_to be_a(AlaveteliPro::PromotionCode)
    end

    it 'ignores an unknown code, as core does for an unknown coupon' do
      subscribe('NOSUCHCODE')

      expect(assigns(:coupon)).to be_nil
    end
  end

  describe 'discount attributes read through to the coupon' do
    let!(:promotion_code) { create_promotion_code }

    subject { AlaveteliPro::PromotionCode.retrieve('SUMMER25') }

    it 'keeps the promotion code id, so Stripe redeems the code' do
      expect(subject.id).to eq(promotion_code.id)
    end

    it 'takes the discount from the underlying coupon' do
      expect(subject.percent_off).to eq(50)
      expect(subject.amount_off).to be_nil
    end

    it 'exposes the typed code as the param' do
      expect(subject.to_param).to eq('SUMMER25')
    end
  end

  describe 'metadata' do
    it 'reads the interval restriction from the coupon' do
      stripe_helper.create_coupon(
        id: 'MONTHLYONLY', percent_off: 50, amount_off: nil, currency: nil,
        metadata: { interval: 'month' }
      )
      create_promotion_code(coupon: 'MONTHLYONLY')

      expect(AlaveteliPro::PromotionCode.retrieve('SUMMER25').metadata)
        .to include(interval: 'month')
    end

    it 'lets the promotion code override the coupon' do
      stripe_helper.create_coupon(
        id: 'TERMED', percent_off: 50, amount_off: nil, currency: nil,
        metadata: { humanized_terms: 'half price' }
      )
      create_promotion_code(
        coupon: 'TERMED', metadata: { humanized_terms: '50% off' }
      )

      expect(AlaveteliPro::PromotionCode.retrieve('SUMMER25').metadata)
        .to include(humanized_terms: '50% off')
    end
  end

  describe 'the interval restriction still applies through a promotion code' do
    let!(:annual_price) do
      stripe_helper.create_price(
        id: 'annual_price', product: product.id, unit_amount: 10_000,
        recurring: { interval: 'year', interval_count: 1 }
      )
    end

    before do
      allow(AlaveteliConfiguration).to receive(:stripe_prices)
        .and_return('pro' => 'pro', 'annual_price' => 'annual')

      stripe_helper.create_coupon(
        id: 'MONTHLYONLY', percent_off: 50, amount_off: nil, currency: nil,
        metadata: { interval: 'month' }
      )
      create_promotion_code(coupon: 'MONTHLYONLY')

      post :create, params: {
        'stripe_token' => token,
        'price_id' => 'annual',
        'coupon_code' => 'SUMMER25'
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

  describe 'refusing a promotion code that cannot be redeemed' do
    shared_examples 'refused before any charge' do |message|
      it 'does not create a subscription' do
        subscribe('SUMMER25')

        expect(assigns(:subscription)).to be_nil
      end

      it 'redirects back to the plan with an error' do
        subscribe('SUMMER25')

        expect(flash[:error]).to eq(message)
        expect(response).to redirect_to(plan_path('pro'))
      end
    end

    # Stripe deactivates a promotion code when it expires or is exhausted, and
    # the lookup only asks for active codes, so a dead code doesn't resolve.
    # Core then charges the list price, exactly as it does for an unknown
    # coupon - the preview tells people before they get that far.
    context 'when the code is no longer active' do
      before { create_promotion_code(active: false) }

      it 'is ignored rather than applied' do
        subscribe('SUMMER25')

        expect(assigns(:coupon)).to be_nil
        expect(assigns(:subscription)).not_to be_nil
      end
    end

    context 'when the underlying coupon is no longer valid' do
      before do
        stripe_helper.create_coupon(
          id: 'DEAD', percent_off: 50, amount_off: nil, currency: nil,
          valid: false
        )
        create_promotion_code(coupon: 'DEAD')
      end

      include_examples 'refused before any charge', 'Coupon code has expired.'
    end

    context 'when the code has reached its redemption limit' do
      before { create_promotion_code(max_redemptions: 2, times_redeemed: 2) }

      include_examples 'refused before any charge', 'Coupon code has expired.'
    end

    context 'when the code carries a minimum amount' do
      # Stripe refuses these on subscriptions outright.
      before do
        create_promotion_code(
          restrictions: {
            first_time_transaction: false,
            minimum_amount: 5000,
            minimum_amount_currency: 'aud'
          }
        )
      end

      include_examples 'refused before any charge', 'Coupon code is invalid.'
    end

    context 'when the code is for new subscribers and the user has invoices' do
      before do
        create_promotion_code(
          restrictions: {
            first_time_transaction: true,
            minimum_amount: nil,
            minimum_amount_currency: nil
          }
        )

        pro_account = FactoryBot.create(:pro_account, user: user)
        allow(pro_account).to receive(:invoices).and_return([double(:invoice)])
        allow(user).to receive(:pro_account).and_return(pro_account)
        allow(controller).to receive(:current_user).and_return(user)
      end

      include_examples 'refused before any charge',
                       'This coupon code is only available to new subscribers.'
    end

    context 'when the code is for new subscribers and the user is new' do
      before do
        create_promotion_code(
          restrictions: {
            first_time_transaction: true,
            minimum_amount: nil,
            minimum_amount_currency: nil
          }
        )
      end

      it 'subscribes the user' do
        subscribe('SUMMER25')

        expect(assigns(:subscription)).not_to be_nil
      end
    end
  end
end
