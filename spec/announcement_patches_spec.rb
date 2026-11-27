# frozen_string_literal: true

# Announcement styles and rich text, backported from
# https://github.com/mysociety/alaveteli/pull/9644 (see
# lib/announcement_patches.rb).
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)
require File.expand_path('support/announcement_factory', __dir__)

RSpec.describe Announcement do
  describe '#rich_body' do
    # Created up front, so the English body is not saved under :es
    let!(:announcement) do
      FactoryBot.create(:announcement, rich_body: 'English body')
    end

    it 'falls back to the default locale when there is no translation' do
      AlaveteliLocalization.with_locale(:es) do
        expect(announcement.rich_body.to_plain_text).to eq('English body')
      end
    end

    it 'prefers the body in the current locale' do
      AlaveteliLocalization.with_locale(:es) do
        announcement.rich_body = 'Cuerpo'
        announcement.save!
      end

      # Found again from the database in each locale, so this checks what was
      # saved and not the object that was edited
      AlaveteliLocalization.with_locale(:es) do
        expect(Announcement.find(announcement.id).rich_body.to_plain_text)
          .to eq('Cuerpo')
      end

      expect(Announcement.find(announcement.id).rich_body.to_plain_text)
        .to eq('English body')
    end
  end

  describe '#content' do
    it 'reads from the rich body' do
      announcement = FactoryBot.build(:announcement, rich_body: 'Hello')
      expect(announcement.content).to eq('Hello')
    end
  end

  describe 'validations' do
    it 'has valid factory' do
      expect(FactoryBot.build(:announcement)).to be_valid
    end

    it 'requires rich_body' do
      announcement = FactoryBot.build(:announcement, rich_body: nil)
      expect(announcement).not_to be_valid
    end

    it 'defaults to the default style' do
      expect(Announcement.new).to be_default_style
    end

    it 'allows the colour styles' do
      %w[red yellow green blue].each do |style|
        expect(FactoryBot.build(:announcement, style: style)).to be_valid
      end
    end

    it 'rejects unknown styles' do
      expect { FactoryBot.build(:announcement, style: 'orange') }
        .to raise_error(ArgumentError)
    end
  end

  describe '.style_labels' do
    it 'offers the default and the colours' do
      expect(Announcement.style_labels.values)
        .to eq(%w[default red yellow green blue])
    end
  end
end
