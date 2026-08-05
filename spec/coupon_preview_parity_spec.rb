# frozen_string_literal: true

# Guards the one thing the rest of coupon_preview_spec.rb cannot: that the
# theme's pre-purchase preview arithmetic agrees with the figure Alaveteli itself
# shows for the same price and coupon after purchase.
#
# The preview has to re-implement the maths because
# AlaveteliPro::Subscription::Discount mixes into a Subscription and cannot be
# called against a bare Price + Coupon. Duplicated arithmetic drifts, and the
# other specs pin literal expected amounts, so they would keep passing while the
# two implementations diverged. This spec compares them directly instead: if
# upstream changes coupon_reduction or Taxable, this fails.
#
# A full "preview == amount Stripe charges" test is not achievable under
# stripe-ruby-mock 4.0.0: its invoice maths ignores tax_percent and inverts
# percent-coupon discounts, and latest_invoice is built from empty line items.
# So this compares the two application-side calculations, and the real
# end-to-end check belongs on staging with a Stripe test card.
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
  let(:currency) { 'GBP' }
  let(:user) { FactoryBot.create(:user) }

  # Upstream's calculation, reached the way upstream reaches it: an object that
  # mixes in AlaveteliPro::Subscription::Discount and exposes the same `plan` and
  # `discount` a real Subscription would. Including the module brings Taxable and
  # `tax :discounted_amount` with it, so #discounted_amount_with_tax here is the
  # identical code path used by
  # app/views/alaveteli_pro/subscriptions/_subscription.html.erb.
  #
  # Note `plan`, not `price`. AlaveteliPro::Subscription defines #price but not
  # #plan, so Discount#discounted_amount's `plan.amount` falls through
  # method_missing to Stripe's legacy single-item subscription.plan, where the
  # attribute is `amount` rather than `unit_amount`. For a single-price
  # subscription the two hold the same value, which is why the theme reading
  # price.unit_amount is equivalent - this spec is what proves that stays true.
  let(:upstream_calculator) do
    Class.new do
      include AlaveteliPro::Subscription::Discount

      attr_reader :plan, :discount, :trial_start, :trial_end

      def initialize(amount, coupon)
        @plan = Struct.new(:amount).new(amount)
        @discount = Struct.new(:coupon).new(coupon)
      end
    end
  end

  before do
    allow(AlaveteliConfiguration).to receive(:stripe_tax_rate).and_return('0.10')
    allow(AlaveteliConfiguration)
      .to receive(:iso_currency_code).and_return(currency)
    sign_in user
  end

  # Compare the raw minor-unit numbers, NOT the strings the endpoint renders.
  # format_currency rounds to the cent, which masks exactly the sub-cent
  # divergence this spec exists to catch.
  def theme_gross(price_id, coupon_code)
    get :coupon_preview,
        params: { price_id: price_id, coupon_code: coupon_code }
    controller.send(:coupon_discounted_gross,
                    AlaveteliPro::Price.retrieve(price_id),
                    AlaveteliPro::Coupon.retrieve(coupon_code))
  end

  def upstream_gross(price_id)
    price = AlaveteliPro::Price.retrieve(price_id)
    coupon = AlaveteliPro::Coupon.retrieve(@coupon_code)
    upstream_calculator
      .new(price.unit_amount, coupon).discounted_amount_with_tax
  end

  # 4500 with a 50% coupon divides evenly, so this passes either side of the
  # rounding question. It is here to prove the harness itself is sound - if this
  # fails, the comparison is wrong rather than the arithmetic.
  context 'with a discount that divides evenly' do
    let!(:price) do
      stripe_helper.create_price(
        id: 'pro', product: product.id, unit_amount: 4500
      )
    end

    let!(:coupon) do
      stripe_helper.create_coupon(
        id: 'HALF', percent_off: 50, amount_off: nil, currency: nil
      )
    end

    it 'computes the same amount upstream would display' do
      @coupon_code = 'HALF'
      expect(theme_gross('pro', @coupon_code)).to eq upstream_gross('pro')
    end
  end

  # The discriminating case. 4499 * 50 / 100 is 2249.5, so an implementation that
  # rounds the reduction and one that does not disagree by a cent. This is what
  # caught the original divergence, and what will catch it coming back.
  context 'with a discount that does not divide evenly' do
    let!(:price) do
      stripe_helper.create_price(
        id: 'pro', product: product.id, unit_amount: 4499
      )
    end

    let!(:coupon) do
      stripe_helper.create_coupon(
        id: 'HALF', percent_off: 50, amount_off: nil, currency: nil
      )
    end

    it 'computes the same amount upstream would display' do
      @coupon_code = 'HALF'
      expect(theme_gross('pro', @coupon_code)).to eq upstream_gross('pro')
    end
  end

  # THE discriminating case. With an Integer percent_off, Ruby's integer division
  # already truncates, so rounding the result is a no-op and a rounding bug hides
  # completely. Real Stripe sends a fractional percent_off (percent_off_precise),
  # and only then do "round the reduction" and "don't" diverge.
  #
  # 900 at 12.5% off with 10% tax is chosen deliberately: it is one of the price
  # points where the divergence survives formatting and a person sees a different
  # price. Rounding the reduction gives 866 (£8.66); not rounding gives 866.5,
  # which formats as £8.67. Most price points hide the difference behind
  # format_currency's rounding to the cent, so a spec that only asserted the
  # rendered string would pass on the wrong arithmetic at most values - hence the
  # numeric assertion as well.
  context 'with a fractional percent_off' do
    let!(:price) do
      stripe_helper.create_price(
        id: 'pro', product: product.id, unit_amount: 900
      )
    end

    let!(:coupon) do
      stripe_helper.create_coupon(
        id: 'TWELVEHALF', percent_off: 12.5, amount_off: nil, currency: nil
      )
    end

    it 'computes the same amount upstream would display' do
      @coupon_code = 'TWELVEHALF'
      expect(theme_gross('pro', @coupon_code)).to eq upstream_gross('pro')
    end

    it 'renders the same price a person would be shown after purchase' do
      @coupon_code = 'TWELVEHALF'
      get :coupon_preview,
          params: { price_id: 'pro', coupon_code: @coupon_code }

      expected = controller.helpers
                           .format_currency(upstream_gross('pro'), no_cents_if_whole: true)

      expect(JSON.parse(response.body).fetch('amount')).to eq expected
      # £ because iso_currency_code is stubbed to GBP above. Rounding the
      # reduction would render £8.66 here - a different price, not a rounding
      # curiosity.
      expect(expected).to eq '£8.67'
    end
  end

  # amount_off takes a different branch of coupon_reduction, and is the one
  # coupon shape where no division happens at all.
  context 'with a fixed amount_off coupon' do
    let!(:price) do
      stripe_helper.create_price(
        id: 'pro', product: product.id, unit_amount: 4499
      )
    end

    let!(:coupon) do
      stripe_helper.create_coupon(
        id: 'TENOFF', amount_off: 1000, currency: currency.downcase
      )
    end

    it 'computes the same amount upstream would display' do
      @coupon_code = 'TENOFF'
      expect(theme_gross('pro', @coupon_code)).to eq upstream_gross('pro')
    end
  end
end
