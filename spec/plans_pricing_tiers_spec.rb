# frozen_string_literal: true

# Exercises the theme's _pricing_tiers.html.erb override (rendered by the
# plans#index view) against the 0.45 Prices API.
#
# The partial builds a single Professional tier from AlaveteliPro::Price.list:
# the headline price from the first entry and an "or {{amount}} ..." link to
# the second. Price.list returns nil for any configured Stripe price id that no
# longer resolves (Stripe::InvalidRequestError), so the view must tolerate both
# a short list and nil entries rather than raising NoMethodError on the public
# pricing page.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)
require 'stripe_mock'

RSpec.describe AlaveteliPro::PlansController, type: :controller do
  render_views

  before { StripeMock.start }
  after { StripeMock.stop }

  let(:stripe_helper) { StripeMock.create_test_helper }
  let(:product) { stripe_helper.create_product }

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
    allow(AlaveteliConfiguration).to receive(:stripe_tax_rate).and_return('0.0')
    allow(AlaveteliConfiguration)
      .to receive(:iso_currency_code).and_return('GBP')
  end

  describe 'GET #index' do
    context 'with monthly and annual prices configured' do
      before do
        allow(AlaveteliConfiguration).to receive(:stripe_prices)
          .and_return('pro' => 'pro', 'annual_price' => 'annual')
        get :index
      end

      it 'renders the headline price' do
        expect(response).to have_http_status(:ok)
        expect(response.body).to have_css('.price-label__amount')
      end

      it 'renders the alternative price option linking to the second plan' do
        expect(response.body)
          .to have_css('.price-label-option a', text: /annually/)
      end

      it 'renders the sign up button' do
        expect(response.body).to have_css('a.button-pop', text: 'Sign up')
      end
    end

    context 'with only a single price configured' do
      before do
        allow(AlaveteliConfiguration).to receive(:stripe_prices)
          .and_return('pro' => 'pro')
        get :index
      end

      it 'renders the headline price without an alternative option' do
        expect(response).to have_http_status(:ok)
        expect(response.body).to have_css('.price-label__amount')
        expect(response.body).to have_no_css('.price-label-option')
      end
    end

    context 'when the first configured price no longer resolves in Stripe' do
      before do
        # 'missing' has no matching Stripe price, so Price.list yields
        # [nil, annual_price]; the view must compact it rather than raise.
        allow(AlaveteliConfiguration).to receive(:stripe_prices)
          .and_return('missing' => 'pro', 'annual_price' => 'annual')
        get :index
      end

      it 'renders the surviving price without raising' do
        expect(response).to have_http_status(:ok)
        expect(response.body).to have_css('.price-label__amount')
      end
    end
  end
end
