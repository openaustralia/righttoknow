# frozen_string_literal: true

# Exercises the theme's live coupon price preview endpoint, added to
# AlaveteliPro::PlansController in lib/controller_patches.rb and routed in
# config/custom-routes.rb.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)
require 'stripe_mock'

RSpec.describe AlaveteliPro::PlansController, type: :controller do # rubocop:disable Metrics/BlockLength
  before { StripeMock.start }
  after { StripeMock.stop }

  let(:stripe_helper) { StripeMock.create_test_helper }
  let(:product) { stripe_helper.create_product }
  let(:currency) { 'GBP' }

  let!(:pro_price) do
    stripe_helper.create_price(
      id: 'pro', product: product.id, unit_amount: 4500
    )
  end

  let(:user) { FactoryBot.create(:user) }

  def json
    JSON.parse(response.body)
  end

  # Format via the app's own helper so expectations track exactly what the
  # endpoint produces (rather than reimplementing Money formatting here).
  def money(cents)
    controller.helpers.format_currency(cents, no_cents_if_whole: true)
  end

  before do
    allow(AlaveteliConfiguration).to receive(:stripe_tax_rate).and_return('0.10')
    allow(AlaveteliConfiguration)
      .to receive(:iso_currency_code).and_return(currency)
  end

  # Verifies the theme's show.html.erb override renders the DOM hooks the
  # coupon preview JS binds to, and that the plan_coupon_preview route helper
  # resolves (i.e. the custom route is loaded).
  describe 'GET #show' do
    render_views

    before do
      sign_in FactoryBot.create(:user)
      get :show, params: { id: 'pro' }
    end

    it 'renders the coupon preview hooks and endpoint URL' do
      expect(response.body)
        .to include('data-preview-url="/plans/pro/coupon_preview"')
      expect(response.body).to include('id="js-plan-price"')
      expect(response.body).to include('id="js-coupon-feedback"')
    end

    it 'includes the coupon preview script' do
      expect(response.body).to include('alaveteli_pro/coupon_preview')
    end
  end

  describe 'GET #coupon_preview' do # rubocop:disable Metrics/BlockLength
    context 'without a signed-in user' do
      before do
        get :coupon_preview, params: { price_id: 'pro', coupon_code: 'X' }
      end

      it 'redirects to the login form' do
        expect(response).to redirect_to(signin_path(token: PostRedirect.last.token))
      end
    end

    context 'with a signed-in user' do # rubocop:disable Metrics/BlockLength
      before { sign_in user }

      context 'with a blank coupon code' do
        before do
          get :coupon_preview, params: { price_id: 'pro', coupon_code: '' }
        end

        it 'returns the list price unchanged' do
          expect(json['status']).to eq('empty')
          expect(json['amount']).to eq(money(4950)) # 4500 + 10% tax
        end
      end

      context 'with a valid percent_off coupon' do
        before do
          # StripeMock's default coupon carries amount_off/currency too; null
          # them so this is a pure percent_off coupon like real Stripe returns.
          stripe_helper.create_coupon(
            id: 'HALF', percent_off: 50, amount_off: nil, currency: nil
          )
          get :coupon_preview, params: { price_id: 'pro', coupon_code: 'HALF' }
        end

        it 'returns the discounted price with tax on the post-discount net' do
          # net 4500 - 50% = 2250; + 10% tax = 2475. Original 4950. Saving 2475.
          expect(json['status']).to eq('valid')
          expect(json['amount']).to eq(money(2475))
          expect(json['original']).to eq(money(4950))
          expect(json['saving']).to eq("You save #{money(2475)}")
        end
      end

      context 'with a valid amount_off coupon' do
        before do
          stripe_helper.create_coupon(
            id: 'TENOFF', amount_off: 1000, currency: currency.downcase
          )
          get :coupon_preview, params: { price_id: 'pro', coupon_code: 'TENOFF' }
        end

        it 'subtracts the amount then applies tax' do
          # net 4500 - 1000 = 3500; + 10% tax = 3850.
          expect(json['status']).to eq('valid')
          expect(json['amount']).to eq(money(3850))
        end
      end

      context 'with a coupon that discounts the whole price' do
        before do
          stripe_helper.create_coupon(
            id: 'FREE', percent_off: 100, amount_off: nil, currency: nil
          )
          get :coupon_preview, params: { price_id: 'pro', coupon_code: 'FREE' }
        end

        it 'clamps at zero rather than going negative' do
          expect(json['status']).to eq('valid')
          expect(json['amount']).to eq(money(0))
        end
      end

      context 'with an unknown coupon code' do
        before do
          get :coupon_preview, params: { price_id: 'pro', coupon_code: 'NOPE' }
        end

        it 'reports the code as invalid' do
          expect(json['status']).to eq('invalid')
          expect(json['message']).to eq('Coupon code is invalid.')
        end
      end

      context 'with a coupon that exists but is no longer valid' do
        before do
          allow(AlaveteliPro::Coupon).to receive(:retrieve)
            .and_return(double(valid: false))
          get :coupon_preview, params: { price_id: 'pro', coupon_code: 'EXPIRED' }
        end

        it 'reports the code as expired' do
          expect(json['status']).to eq('expired')
          expect(json['message']).to eq('Coupon code has expired.')
        end
      end

      context 'with an amount_off coupon in a different currency' do
        before do
          stripe_helper.create_coupon(
            id: 'USDOFF', amount_off: 1000, currency: 'usd'
          )
          get :coupon_preview, params: { price_id: 'pro', coupon_code: 'USDOFF' }
        end

        it 'refuses to apply a mismatched-currency discount' do
          expect(json['status']).to eq('invalid')
        end
      end

      # A coupon carrying an `interval` metadata restriction (e.g. a
      # monthly-only coupon) must only preview against a price with a matching
      # billing interval. Stripe's product-scoped applies_to can't distinguish
      # the monthly and annual prices within the Pro product, so the restriction
      # lives in coupon metadata and is enforced here and at checkout (see
      # lib/controller_patches.rb).
      context 'with a coupon restricted to the matching interval' do
        before do
          # pro_price is monthly (StripeMock defaults recurring.interval to
          # "month").
          stripe_helper.create_coupon(
            id: 'MONTHLYONLY', percent_off: 50, amount_off: nil, currency: nil,
            metadata: { interval: 'month' }
          )
          get :coupon_preview,
              params: { price_id: 'pro', coupon_code: 'MONTHLYONLY' }
        end

        it 'previews the discount' do
          expect(json['status']).to eq('valid')
          expect(json['amount']).to eq(money(2475)) # 4500 - 50% + 10% tax
        end
      end

      context 'with a coupon restricted to a non-matching interval' do
        let!(:annual_price) do
          stripe_helper.create_price(
            id: 'annual_price', product: product.id, unit_amount: 45_000,
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
          get :coupon_preview,
              params: { price_id: 'annual', coupon_code: 'MONTHLYONLY' }
        end

        it 'refuses to apply the coupon to the wrong plan' do
          expect(json['status']).to eq('invalid')
          expect(json['message'])
            .to eq('This coupon code cannot be used with this plan.')
        end
      end

      # A promotion code resolves through the same path as a coupon, so the
      # preview and checkout can't disagree - see
      # AlaveteliPro::DiscountCodeResolution and spec/promotion_code_spec.rb.
      context 'with a promotion code' do
        before do
          stripe_helper.create_coupon(
            id: 'HALF', percent_off: 50, amount_off: nil, currency: nil
          )
          Stripe::PromotionCode.create(coupon: 'HALF', code: 'SUMMER25')
          get :coupon_preview,
              params: { price_id: 'pro', coupon_code: 'SUMMER25' }
        end

        it "previews the underlying coupon's discount" do
          expect(json['status']).to eq('valid')
          expect(json['amount']).to eq(money(2475)) # 4500 - 50% + 10% tax
        end
      end

      context 'with a promotion code that is no longer active' do
        before do
          stripe_helper.create_coupon(
            id: 'HALF', percent_off: 50, amount_off: nil, currency: nil
          )
          Stripe::PromotionCode.create(
            coupon: 'HALF', code: 'SUMMER25', active: false
          )
          get :coupon_preview,
              params: { price_id: 'pro', coupon_code: 'SUMMER25' }
        end

        # Stripe deactivates a promotion code when it expires or is exhausted,
        # and the lookup only asks for active codes, so a dead code doesn't
        # resolve at all and reads as invalid rather than expired.
        it 'reports the code as invalid' do
          expect(json['status']).to eq('invalid')
          expect(json['message']).to eq('Coupon code is invalid.')
        end
      end

      context 'with an unknown price_id' do
        before do
          get :coupon_preview, params: { price_id: 'nope', coupon_code: 'HALF' }
        end

        it 'returns not found' do
          expect(response).to have_http_status(:not_found)
          expect(json['status']).to eq('error')
        end
      end
    end
  end
end
