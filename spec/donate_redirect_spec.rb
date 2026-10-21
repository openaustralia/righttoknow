# frozen_string_literal: true

# Exercises the /donate redirect in lib/config/custom-routes.rb and the
# DonationUrl builder (lib/donation_url.rb) behind it and the theme's donate
# links.
#
# AlaveteliConfiguration.donation_url is stubbed because its value comes from
# the host's config/general.yml, which differs between machines, and one
# example needs it blank.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)

RSpec.describe 'Donate redirect', type: :request do
  let(:tags) { 'utm_source=righttoknow&utm_medium=link' }

  def stub_donation_url(url)
    allow(AlaveteliConfiguration).to receive(:donation_url).and_return(url)
  end

  describe 'GET /donate' do
    before { stub_donation_url('https://donate.example.test/') }

    it 'temporarily redirects to DONATION_URL with UTMs' do
      get '/donate'

      expect(response).to have_http_status(:found)
      expect(response.location).to eq(
        "https://donate.example.test/?#{tags}&utm_campaign=donate-redirect"
      )
    end

    it 'ignores incoming query parameters' do
      get '/donate?utm_campaign=other&foo=bar'

      expect(response.location).to eq(
        "https://donate.example.test/?#{tags}&utm_campaign=donate-redirect"
      )
    end

    it 'keeps any query string already on DONATION_URL' do
      stub_donation_url('https://donate.example.test/?appeal=general')

      get '/donate'

      expect(response.location).to eq(
        "https://donate.example.test/?appeal=general&#{tags}&utm_campaign=donate-redirect"
      )
    end

    it 'is not routed when DONATION_URL is blank' do
      stub_donation_url('')

      expect { get '/donate' }.to raise_error(ApplicationController::RouteNotFound)
    end
  end

  describe 'donate links in views' do
    before { stub_donation_url('https://donate.example.test/') }

    it 'tags the link on the About page' do
      get '/help/about'

      expect(response.body).to include(
        'https://donate.example.test/?utm_source=righttoknow&amp;utm_medium=link' \
        '&amp;utm_campaign=donate-link&amp;utm_content=about'
      )
    end

    it 'tags the link on the Credits page' do
      get '/help/credits'

      expect(response.body).to include('utm_content=credits')
    end

    it 'tags the footer link' do
      get '/help/privacy'

      expect(response.body).to include('utm_content=footer')
    end

    it 'leaves out the About and Credits donate links when DONATION_URL is blank' do
      stub_donation_url('')

      get '/help/about'
      expect(response.body).not_to include('utm_content=about')

      get '/help/credits'
      expect(response.body).not_to include('utm_content=credits')
    end

    it 'leaves out the footer donate button when DONATION_URL is blank' do
      stub_donation_url('')

      get '/help/privacy'

      expect(response.body).not_to include('oaf-footer__donate')
    end
  end
end
