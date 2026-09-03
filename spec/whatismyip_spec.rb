# frozen_string_literal: true

# Exercises lib/whatismyip_controller.rb, routed in lib/config/custom-routes.rb.
#
# Cloudflare's range lists are stubbed with WebMock rather than fetched for
# real, so the spec doesn't depend on cloudflare.com being reachable. The
# stubbing is at the HTTP layer, so the controller's own Net::HTTP call runs as
# written. Rails.cache is real (:null_store in test, per
# config/environments/test.rb) so the fetch/validate block in cloudflare_ranges
# actually runs on every request - important since one of the bugs this spec
# guards against (a bad fetch getting cached and poisoning every check for 24
# hours) is specifically about what happens inside that block.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)

RSpec.shared_context 'stubbed Cloudflare ranges' do
  def ipv4_url = 'https://www.cloudflare.com/ips-v4'
  def ipv6_url = 'https://www.cloudflare.com/ips-v6'

  def full_ipv4 = %w[173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22]
  def full_ipv6 = %w[2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32]

  def stub_ranges(url, cidrs)
    stub_request(:get, url).to_return(status: 200, body: cidrs.join("\n"))
  end

  def stub_healthy_cloudflare
    stub_ranges(ipv4_url, full_ipv4)
    stub_ranges(ipv6_url, full_ipv6)
  end
end

RSpec.describe WhatismyipController, type: :controller do
  include_context 'stubbed Cloudflare ranges'

  # A default stub is needed alongside the PROVIDE_WHATISMYIP one: rendering
  # goes through ApplicationController#set_gettext_locale, which reads other
  # settings, and a bare `with` stub would make those raise.
  def stub_whatismyip_setting(enabled)
    allow(AlaveteliConfiguration).to receive(:get).and_call_original
    allow(AlaveteliConfiguration).to receive(:get)
      .with('PROVIDE_WHATISMYIP', false).and_return(enabled)
  end

  describe 'GET #index' do
    context 'when PROVIDE_WHATISMYIP is off' do
      it 'is not found' do
        stub_whatismyip_setting(false)
        get :index
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when PROVIDE_WHATISMYIP is on' do
      before { stub_whatismyip_setting(true) }

      context 'with a healthy Cloudflare response' do
        before { stub_healthy_cloudflare }

        it 'returns the IP alone when outside Cloudflare\'s ranges' do
          request.remote_addr = '1.2.3.4'
          get :index
          expect(response.body).to eq('1.2.3.4')
        end

        it 'appends FAIL when inside Cloudflare\'s ranges' do
          request.remote_addr = '173.245.48.1'
          get :index
          expect(response.body).to eq('173.245.48.1 FAIL')
        end
      end

      context 'when Cloudflare returns an error status' do
        before do
          stub_request(:get, ipv4_url).to_return(status: 500)
          stub_ranges(ipv6_url, full_ipv6)
          request.remote_addr = '1.2.3.4'
        end

        it 'reports UNABLE TO CHECK rather than caching the failure' do
          get :index
          expect(response.body).to eq('1.2.3.4 UNABLE TO CHECK')
        end

        it 'recovers once Cloudflare responds normally again' do
          get :index

          stub_healthy_cloudflare
          get :index

          expect(response.body).to eq('1.2.3.4')
        end
      end

      context 'when one list is suspiciously truncated' do
        before do
          # A full-sized v4 list must not offset a truncated v6 one - each is
          # checked independently.
          stub_ranges(ipv4_url, full_ipv4)
          stub_ranges(ipv6_url, %w[2400:cb00::/32])
          request.remote_addr = '1.2.3.4'
        end

        it 'reports UNABLE TO CHECK rather than trusting the truncated list' do
          get :index
          expect(response.body).to eq('1.2.3.4 UNABLE TO CHECK')
        end
      end
    end
  end
end

# The point of this action is to report what nginx actually handed Rails, so it
# has to be exercised through the middleware stack: ActionDispatch::RemoteIp,
# which is what would mask a Cloudflare peer address behind a forwarded visitor
# IP, only runs on a real request.
RSpec.describe 'GET /whatismyip', type: :request do
  include_context 'stubbed Cloudflare ranges'

  before do
    allow(AlaveteliConfiguration).to receive(:get).and_call_original
    allow(AlaveteliConfiguration).to receive(:get)
      .with('PROVIDE_WHATISMYIP', false).and_return(true)
    stub_healthy_cloudflare
  end

  it 'reports the peer address, not the forwarded visitor IP' do
    get '/whatismyip', headers: {
      'REMOTE_ADDR' => '173.245.48.1',
      'X-Forwarded-For' => '1.2.3.4'
    }

    expect(response.body).to eq('173.245.48.1 FAIL')
  end
end
