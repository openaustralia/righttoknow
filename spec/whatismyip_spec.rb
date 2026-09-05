# frozen_string_literal: true

# Exercises lib/whatismyip_controller.rb, routed in lib/config/custom-routes.rb.
#
# Net::HTTP is stubbed rather than exercised for real so the spec doesn't
# depend on cloudflare.com being reachable. Rails.cache is real (:null_store
# in test, per config/environments/test.rb) so the fetch/validate block in
# cloudflare_ranges actually runs on every request - important since the bug
# this spec guards against (a bad fetch getting cached and poisoning every
# check for 24 hours) is specifically about what happens inside that block.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)

RSpec.describe WhatismyipController, type: :controller do
  def stub_cloudflare(ipv4:, ipv6:)
    responses = {
      'https://www.cloudflare.com/ips-v4' => ipv4,
      'https://www.cloudflare.com/ips-v6' => ipv6
    }
    allow(Net::HTTP).to receive(:get_response) do |uri|
      responses.fetch(uri.to_s)
    end
  end

  def success(*cidrs)
    double('response', is_a?: true, body: cidrs.join("\n"))
  end

  def failure
    double('response', is_a?: false)
  end

  describe 'GET #index' do
    context 'when PROVIDE_WHATISMYIP is off' do
      it 'is not found' do
        allow(AlaveteliConfiguration).to receive(:get)
          .with('PROVIDE_WHATISMYIP', false).and_return(false)
        get :index
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when PROVIDE_WHATISMYIP is on' do
      before do
        allow(AlaveteliConfiguration).to receive(:get)
          .with('PROVIDE_WHATISMYIP', false).and_return(true)
      end

      context 'with a healthy Cloudflare response' do
        before do
          stub_cloudflare(
            ipv4: success('173.245.48.0/20', '103.21.244.0/22', '103.22.200.0/22', '103.31.4.0/22'),
            ipv6: success('2400:cb00::/32', '2606:4700::/32', '2803:f800::/32', '2405:b500::/32')
          )
        end

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
          stub_cloudflare(ipv4: failure, ipv6: success('2400:cb00::/32'))
          request.remote_addr = '1.2.3.4'
        end

        it 'reports UNABLE TO CHECK rather than caching the failure' do
          get :index
          expect(response.body).to eq('1.2.3.4 UNABLE TO CHECK')
        end

        it 'recovers once Cloudflare responds normally again' do
          get :index

          stub_cloudflare(
            ipv4: success('173.245.48.0/20', '103.21.244.0/22', '103.22.200.0/22', '103.31.4.0/22'),
            ipv6: success('2400:cb00::/32', '2606:4700::/32', '2803:f800::/32', '2405:b500::/32')
          )
          get :index

          expect(response.body).to eq('1.2.3.4')
        end
      end

      context 'when one list is suspiciously truncated' do
        before do
          # A full-sized v4 list must not offset a truncated v6 one - each is
          # checked independently.
          stub_cloudflare(
            ipv4: success('173.245.48.0/20', '103.21.244.0/22', '103.22.200.0/22', '103.31.4.0/22'),
            ipv6: success('2400:cb00::/32')
          )
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

# Guards against issue #1100: in development ApplicationController is
# reloadable, so after every code reload it is a brand-new class object while
# the theme's hand-defined WhatismyipController constant survives, still
# subclassing the old one. Re-running the theme's to_prepare block then raised
# "superclass mismatch", which broke docker/setup (db:migrate reloads before
# db:seed) and every dev-mode reload.
#
# A real reload can't reproduce this here - the test environment doesn't
# reload classes, so ApplicationController would keep its identity - so this
# simulates one instead: swap ApplicationController for a fresh class object
# (exactly what a dev reload does) and re-run the theme's registered
# to_prepare block, restoring both afterwards.
RSpec.describe 'WhatismyipController code reloading' do
  def theme_to_prepare_block
    Rails.application.reloader._prepare_callbacks.map(&:filter).find do |filter|
      filter.respond_to?(:source_location) &&
        filter.source_location&.first&.end_with?('whatismyip_controller.rb')
    end
  end

  it 'redefines the controller when ApplicationController is a new class object' do
    block = theme_to_prepare_block
    expect(block).not_to be_nil

    original = ApplicationController
    begin
      Object.send(:remove_const, :ApplicationController)
      Object.const_set(:ApplicationController, Class.new(original))

      expect { block.call }.not_to raise_error
      expect(WhatismyipController.superclass).to eq(ApplicationController)
    ensure
      Object.send(:remove_const, :ApplicationController)
      Object.const_set(:ApplicationController, original)
      # Leave WhatismyipController subclassing the real class again
      block.call
    end
  end
end
