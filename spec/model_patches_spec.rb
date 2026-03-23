# frozen_string_literal: true

# Tells Alaveteli's theme loader to load the righttoknow theme during test setup,
# so that the PublicBody and InfoRequest patches from lib/model_patches.rb are applied.
ALAVETELI_TEST_THEME = 'righttoknow' unless defined?(ALAVETELI_TEST_THEME)
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper'))

# Tests for the PublicBody patches added by this theme. These patches add
# Australian jurisdiction awareness to public bodies, driven by tags set in
# the Alaveteli admin interface (e.g. "NSW", "QLD", "federal").
RSpec.describe PublicBody do
  # jurisdiction maps the authority's tag to a symbol used by the other
  # patched methods to look up jurisdiction-specific values.
  describe '#jurisdiction' do
    subject { public_body.jurisdiction }

    context 'with ACT tag' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'ACT') }
      it { is_expected.to eq(:act) }
    end

    context 'with NSW tag' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'NSW') }
      it { is_expected.to eq(:nsw) }
    end

    context 'with NT tag' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'NT') }
      it { is_expected.to eq(:nt) }
    end

    context 'with QLD tag' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'QLD') }
      it { is_expected.to eq(:qld) }
    end

    context 'with SA tag' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'SA') }
      it { is_expected.to eq(:sa) }
    end

    context 'with TAS tag' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'TAS') }
      it { is_expected.to eq(:tas) }
    end

    context 'with VIC tag' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'VIC') }
      it { is_expected.to eq(:vic) }
    end

    context 'with WA tag' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'WA') }
      it { is_expected.to eq(:wa) }
    end

    context 'with federal tag' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'federal') }
      it { is_expected.to eq(:federal) }
    end

    context 'with no jurisdiction tag' do
      let(:public_body) { FactoryBot.create(:public_body) }
      it { is_expected.to be_nil }
    end
  end

  # reply_late_after_days returns how many days an authority has to respond
  # before Alaveteli considers them overdue. Each Australian jurisdiction has
  # a different statutory timeframe set by the relevant FOI legislation.
  describe '#reply_late_after_days' do
    subject { public_body.reply_late_after_days }

    context 'with NSW jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'NSW') }
      it { is_expected.to eq(20) }
    end

    context 'with TAS jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'TAS') }
      it { is_expected.to eq(20) }
    end

    context 'with QLD jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'QLD') }
      it { is_expected.to eq(25) }
    end

    context 'with federal jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'federal') }
      it { is_expected.to eq(30) }
    end

    context 'with ACT jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'ACT') }
      it { is_expected.to eq(30) }
    end

    context 'with NT jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'NT') }
      it { is_expected.to eq(30) }
    end

    context 'with SA jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'SA') }
      it { is_expected.to eq(30) }
    end

    context 'with VIC jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'VIC') }
      it { is_expected.to eq(45) }
    end

    context 'with WA jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'WA') }
      it { is_expected.to eq(45) }
    end

    # Authorities without a jurisdiction tag fall back to Alaveteli's global
    # default, configured in general.yml.
    context 'with no jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body) }
      it { is_expected.to eq(AlaveteliConfiguration.reply_late_after_days) }
    end
  end
end

RSpec.describe PublicBody do
  # working_or_calendar_days determines whether the deadline is counted in
  # working days or calendar days, which varies by jurisdiction.
  describe '#working_or_calendar_days' do
    subject { public_body.working_or_calendar_days }

    context 'with NSW jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'NSW') }
      it { is_expected.to eq('working') }
    end

    context 'with TAS jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'TAS') }
      it { is_expected.to eq('working') }
    end

    context 'with QLD jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'QLD') }
      it { is_expected.to eq('working') }
    end

    context 'with ACT jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'ACT') }
      it { is_expected.to eq('calendar') }
    end

    context 'with federal jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'federal') }
      it { is_expected.to eq('calendar') }
    end

    context 'with VIC jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'VIC') }
      it { is_expected.to eq('calendar') }
    end

    context 'with no jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body) }
      it { is_expected.to eq('calendar') }
    end
  end

  # legislation returns the Legislation object for the authority's jurisdiction.
  # This theme adds GIPA (NSW) and RTI (QLD, TAS) to Alaveteli's default FOI/EIR
  # legislation by overriding Legislation.all in lib/model_patches.rb.
  describe '#legislation' do
    subject { public_body.legislation }

    context 'with NSW jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'NSW') }
      it { is_expected.to eq(Legislation.find!('gipa')) }
    end

    context 'with QLD jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'QLD') }
      it { is_expected.to eq(Legislation.find!('rti')) }
    end

    context 'with TAS jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'TAS') }
      it { is_expected.to eq(Legislation.find!('rti')) }
    end

    context 'with ACT jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'ACT') }
      it { is_expected.to eq(Legislation.find!('foi')) }
    end

    context 'with federal jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body, tag_string: 'federal') }
      it { is_expected.to eq(Legislation.find!('foi')) }
    end

    context 'with no jurisdiction' do
      let(:public_body) { FactoryBot.create(:public_body) }
      it { is_expected.to eq(Legislation.find!('foi')) }
    end
  end

  # info_requests_hidden_count returns the number of requests against this
  # authority that have been given a non-normal prominence (i.e. hidden or
  # backpage), which are not publicly visible on the site.
  describe '#info_requests_hidden_count' do
    let(:public_body) { FactoryBot.create(:public_body) }

    before do
      FactoryBot.create(:info_request, public_body: public_body)
      FactoryBot.create(:info_request, :hidden, public_body: public_body)
      FactoryBot.create(:info_request, :backpage, public_body: public_body)
    end

    it 'counts requests with non-normal prominence' do
      expect(public_body.info_requests_hidden_count).to eq(2)
    end

    it 'excludes requests with normal prominence' do
      expect(public_body.info_requests_hidden_count).not_to eq(3)
    end
  end
end

# Tests for the InfoRequest patch added by this theme. The patch overrides
# date_response_required_by to use the public body's jurisdiction-specific
# deadline (days and day type) instead of Alaveteli's global default.
RSpec.describe InfoRequest do
  # Smoke tests: verify that creating a request against an authority with any
  # jurisdiction tag does not raise an error. This guards against regressions
  # where the theme's to_prepare patches break InfoRequest initialisation.
  describe 'creation against a jurisdiction-tagged authority' do
    %w[ACT NSW NT QLD SA TAS VIC WA federal].each do |tag|
      it "can be created against an authority tagged #{tag}" do
        public_body = FactoryBot.create(:public_body, tag_string: tag)
        expect { FactoryBot.create(:info_request, public_body: public_body) }.not_to raise_error
      end
    end

    it 'can be created against an authority with no jurisdiction tag' do
      public_body = FactoryBot.create(:public_body)
      expect { FactoryBot.create(:info_request, public_body: public_body) }.not_to raise_error
    end
  end

  # date_response_required_by delegates to Holiday.due_date_from, passing the
  # jurisdiction-specific number of days and day type from the associated
  # public body. These tests verify the correct values are passed for each
  # jurisdiction by creating a real authority and request, then checking what
  # arguments Holiday.due_date_from receives.
  describe '#date_response_required_by' do
    let(:expected_date) { Date.new(2025, 1, 31) }

    before { allow(Holiday).to receive(:due_date_from).and_return(expected_date) }

    shared_examples 'calculates due date' do |tag:, days:, day_type:|
      context "with a #{tag || 'no'} tag authority" do
        let(:public_body) { FactoryBot.create(:public_body, tag_string: tag) }
        let(:info_request) { FactoryBot.create(:info_request, public_body: public_body) }

        it "passes #{days} #{day_type} days to Holiday.due_date_from" do
          info_request.date_response_required_by
          expect(Holiday).to have_received(:due_date_from).with(
            info_request.date_initial_request_last_sent_at,
            days,
            day_type
          )
        end

        it 'returns the date from Holiday.due_date_from' do
          expect(info_request.date_response_required_by).to eq(expected_date)
        end
      end
    end

    include_examples 'calculates due date', tag: 'NSW', days: 20, day_type: 'working'
    include_examples 'calculates due date', tag: 'TAS', days: 20, day_type: 'working'
    include_examples 'calculates due date', tag: 'QLD', days: 25, day_type: 'working'
    include_examples 'calculates due date', tag: 'federal', days: 30, day_type: 'calendar'
    include_examples 'calculates due date', tag: 'ACT', days: 30, day_type: 'calendar'
    include_examples 'calculates due date', tag: 'NT', days: 30, day_type: 'calendar'
    include_examples 'calculates due date', tag: 'SA', days: 30, day_type: 'calendar'
    include_examples 'calculates due date', tag: 'VIC', days: 45, day_type: 'calendar'
    include_examples 'calculates due date', tag: 'WA', days: 45, day_type: 'calendar'

    # Authorities without a jurisdiction tag use Alaveteli's configured global
    # default and always count in calendar days.
    context 'with no jurisdiction tag' do
      let(:public_body) { FactoryBot.create(:public_body) }
      let(:info_request) { FactoryBot.create(:info_request, public_body: public_body) }

      it 'passes the configured default days to Holiday.due_date_from' do
        info_request.date_response_required_by
        expect(Holiday).to have_received(:due_date_from).with(
          info_request.date_initial_request_last_sent_at,
          AlaveteliConfiguration.reply_late_after_days,
          'calendar'
        )
      end
    end
  end
end
