# frozen_string_literal: true

# Guards the "Plus, all the power of Right to Know" marketing section,
# reframed in library terms (issue #1038). The section renders from two
# places: the theme's account_request/_marketing_standard_features.html.erb
# override on /pro, and the theme's plans/index.html.erb on /pro/pricing.
# Both are asserted here so the pages can't silently diverge.
#
# The "public record" bullet is deliberately unchanged: it preserves the
# notice that requests and responses become public.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)
require 'stripe_mock'

RSpec.shared_examples 'library-framed standard features' do
  it 'describes the service as a library' do
    expect(response.body).to include('Australia’s best-known FOI library')
    expect(response.body).not_to include('best-known FOI service')
  end

  it 'describes contact details as a collection' do
    expect(response.body).to include(
      '<strong class="marketing-highlight">collection of contact ' \
      'details</strong>'
    )
    expect(response.body).not_to include('database of')
  end

  it 'describes requests as a searchable library' do
    expect(response.body).to include(
      '<strong class="marketing-highlight">searchable library</strong>'
    )
    expect(response.body).not_to include('searchable archive')
  end

  it 'keeps the public record notice' do
    expect(response.body).to include(
      '<strong class="marketing-highlight">public record</strong>'
    )
  end
end

RSpec.describe AlaveteliPro::AccountRequestController, type: :controller do
  render_views

  describe 'GET #index' do
    before { get :index }

    include_examples 'library-framed standard features'
  end
end

RSpec.describe AlaveteliPro::PlansController, type: :controller do
  render_views

  before { StripeMock.start }
  after { StripeMock.stop }

  let(:stripe_helper) { StripeMock.create_test_helper }
  let(:product) { stripe_helper.create_product }

  let!(:monthly_price) do
    stripe_helper.create_price(
      id: 'pro', product: product.id, unit_amount: 1000
    )
  end

  before do
    allow(AlaveteliConfiguration).to receive(:stripe_tax_rate).and_return('0.0')
    allow(AlaveteliConfiguration)
      .to receive(:iso_currency_code).and_return('GBP')
    allow(AlaveteliConfiguration).to receive(:stripe_prices)
      .and_return('pro' => 'pro')
  end

  describe 'GET #index' do
    before { get :index }

    include_examples 'library-framed standard features'
  end
end
