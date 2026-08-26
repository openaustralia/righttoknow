# frozen_string_literal: true

# Exercises lib/whoami_controller.rb, routed in lib/config/custom-routes.rb.
#
# Rails.cache is stubbed rather than exercised for real so the spec doesn't
# depend on cloudflare.com being reachable; the stubbed list is a real
# Cloudflare-published range so the pass/fail examples mean something.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)

RSpec.describe WhoamiController, type: :controller do
  before do
    allow(Rails.cache).to receive(:fetch).and_return(['173.245.48.0/20'])
  end

  describe 'GET #index' do
    context 'when PROVIDE_WHOAMI is off' do
      before do
        allow(AlaveteliConfiguration).to receive(:get)
          .with('PROVIDE_WHOAMI', false).and_return(false)
        get :index
      end

      it 'is not found' do
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when PROVIDE_WHOAMI is on' do
      before do
        allow(AlaveteliConfiguration).to receive(:get)
          .with('PROVIDE_WHOAMI', false).and_return(true)
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
  end
end
