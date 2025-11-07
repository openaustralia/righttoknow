# frozen_string_literal: true

# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper'))

describe HelpPageHistory do
  describe '#commits_url' do
    subject { described_class.new(template).commits_url }

    context 'with a custom help page' do
      let(:template) do
        double(inspect: 'lib/themes/righttoknow/lib/views/' \
                        'help/house_rules.html.erb')
      end

      it do
        is_expected.to eq('https://github.com/openaustralia/righttoknow/' \
                          'commits/production/lib/views/help/house_rules.html.erb')
      end
    end
  end
end
