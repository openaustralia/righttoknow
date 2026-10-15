# frozen_string_literal: true

# Rendering helpers for styled announcements, backported from
# https://github.com/mysociety/alaveteli/pull/9644 (see
# lib/announcement_patches.rb).
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)
require File.expand_path('support/announcement_factory', __dir__)

RSpec.describe AnnouncementStyleHelper, type: :helper do
  describe '#announcement_as_html' do
    let(:announcement) do
      FactoryBot.build(:announcement, rich_body: '<b>Exciting news!</b>')
    end

    it { expect(helper.announcement_as_html(announcement)).to eq('<b>Exciting news!</b>') }

    it 'strips out dangerous tags' do
      announcement.rich_body = '<b>Hi</b><script>alert("!")</script>'
      expect(helper.announcement_as_html(announcement)).not_to include('<script>')
    end

    it 'renders attachments added in the editor' do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("\x89PNG\r\n\x1a\n"),
        filename: 'logo.png',
        content_type: 'image/png'
      )
      attachment = ActionText::Attachment.from_attachable(blob)
      announcement.rich_body = "<div>Hi #{attachment.to_html}</div>"

      expect(helper.announcement_as_html(announcement)).to include('<img', 'logo.png')
    end
  end

  describe '#announcement_style_class' do
    it 'returns a class for the style' do
      announcement = FactoryBot.build(:announcement, style: 'red')
      expect(helper.announcement_style_class(announcement))
        .to eq('announcement--style-red')
    end
  end

  describe '#announcement_admin_alert_class' do
    {
      'red' => 'alert-error',
      'yellow' => 'alert-warning',
      'green' => 'alert-success',
      'blue' => 'alert-info',
      'default' => 'alert-info'
    }.each do |style, alert_class|
      it "maps #{style} to #{alert_class}" do
        announcement = FactoryBot.build(:announcement, style: style)
        expect(helper.announcement_admin_alert_class(announcement)).to eq(alert_class)
      end
    end
  end
end
