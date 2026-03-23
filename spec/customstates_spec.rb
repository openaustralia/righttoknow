# frozen_string_literal: true

# Tells Alaveteli's theme loader to load the righttoknow theme during test setup,
# so that InfoRequestCustomStates and RequestControllerCustomStates are mixed in
# to InfoRequest and the request controller respectively.
ALAVETELI_TEST_THEME = 'righttoknow' unless defined?(ALAVETELI_TEST_THEME)
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper'))

# InfoRequestCustomStates is a module defined in lib/customstates.rb and mixed
# in to InfoRequest by the theme. It adds a custom "transferred" request state,
# which is used when an authority transfers a request to a different public body.
RSpec.describe InfoRequestCustomStates do
  # theme_extra_states tells Alaveteli about the custom states added by this theme.
  describe '.theme_extra_states' do
    subject { InfoRequest.theme_extra_states }

    it { is_expected.to eq(['transferred']) }
  end

  # theme_display_status returns a human-readable label for a given status.
  # For the "transferred" state it returns a translated string; for any other
  # status it raises, since the theme is only responsible for its own states.
  describe '.theme_display_status' do
    subject { InfoRequest.theme_display_status(status) }

    context "with 'transferred' status" do
      let(:status) { 'transferred' }
      it { is_expected.to eq('Transferred.') }
    end

    context 'with an unknown status' do
      let(:status) { 'unknown_status' }
      it { expect { subject }.to raise_error(RuntimeError, /unknown status/) }
    end
  end

  # theme_calculate_status is called by Alaveteli to determine the current
  # state of a request. This theme has no custom calculation logic, so it
  # delegates entirely to Alaveteli's base implementation.
  describe '#theme_calculate_status' do
    let(:info_request) { FactoryBot.create(:info_request) }

    it 'delegates to base_calculate_status' do
      expect(info_request).to receive(:base_calculate_status).and_call_original
      info_request.theme_calculate_status
    end
  end
end

# RequestControllerCustomStates is mixed in to the request controller and handles
# what happens after a user classifies a request as "transferred". It sets a flash
# message and redirects back to the request page.
RSpec.describe RequestControllerCustomStates do
  describe '#theme_describe_state' do
    # Use a plain hash to capture flash assignments, since we're testing the
    # module outside of a real Rails controller.
    let(:flash_store) { {} }
    let(:info_request) { double('InfoRequest', calculate_status: 'transferred', id: 1) }

    # Build a minimal anonymous controller class that includes the module under
    # test and stubs the Rails controller helpers it depends on.
    let(:controller) do
      flash = flash_store
      controller_class = Class.new do
        include RequestControllerCustomStates

        define_method(:flash) { flash }
        define_method(:redirect_to) { |_url| }
        define_method(:request_url) { |_req| '/requests/1' }
        # Stub the Alaveteli translation helper
        define_method(:_) { |str| str }
      end
      controller_class.new
    end

    # @info_request is the instance variable the controller uses for redirect_to
    before { controller.instance_variable_set(:@info_request, info_request) }

    context 'when the request has been transferred' do
      it 'sets a flash notice about the transfer' do
        controller.theme_describe_state(info_request)
        expect(flash_store[:notice]).to include('transferred')
      end

      it 'redirects to the request page' do
        expect(controller).to receive(:redirect_to).with('/requests/1')
        controller.theme_describe_state(info_request)
      end
    end

    # theme_describe_state should only ever be called for states the theme owns.
    # Any other status means something has gone wrong in Alaveteli's dispatch.
    context 'when the calculate_status is not transferred' do
      let(:info_request) { double('InfoRequest', calculate_status: 'waiting_response') }

      it 'raises an error for unknown status' do
        expect { controller.theme_describe_state(info_request) }.to raise_error(
          RuntimeError, /unknown calculate_status/
        )
      end
    end
  end
end
