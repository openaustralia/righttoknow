# frozen_string_literal: true

# The three places an announcement is shown, backported from
# https://github.com/mysociety/alaveteli/pull/9644 (see
# lib/announcement_patches.rb).
#
# View specs don't run the controller callback that puts the theme's views
# ahead of the host's, so each example group does it itself. The style class
# assertions only pass against the theme's views.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)
require File.expand_path('support/announcement_factory', __dir__)

THEME_VIEWS = File.expand_path('../lib/views', __dir__)

RSpec.describe 'general/_site_wide_announcement', type: :view do
  let(:announcement) do
    FactoryBot.create(
      :announcement,
      rich_body: '<b>Exciting news!</b> <script>alert("!")</script>'
    )
  end

  before do
    controller.prepend_view_path(THEME_VIEWS)
    allow(view).to receive(:current_user).and_return(FactoryBot.build(:user))
  end

  def render_announcement
    render template: 'general/_site_wide_announcement',
           locals: { announcement: announcement }
  end

  it 'shows the announcement' do
    render_announcement
    expect(rendered).to include('Introducing projects')
    expect(rendered).to include('<b>Exciting news!</b>')
  end

  it 'strips out dangerous tags' do
    render_announcement
    expect(rendered).not_to include('<script>')
  end

  it 'adds a class for the style, keeping the existing hooks' do
    announcement.update!(style: 'red')
    render_announcement
    expect(rendered).to include('announcement--style-red')
    expect(rendered).to include('id="standard-popup"')
    expect(rendered).to include('popup--standard')
  end
end

RSpec.describe 'admin_general/_announcement', type: :view do
  let(:announcement) do
    FactoryBot.create(
      :announcement,
      visibility: 'admin',
      rich_body: '<b>Exciting news!</b> <script>alert("!")</script>'
    )
  end

  before { controller.prepend_view_path(THEME_VIEWS) }

  def render_announcement
    render template: 'admin_general/_announcement',
           locals: { announcement: announcement }
  end

  it 'shows the announcement' do
    render_announcement
    expect(rendered).to include('Introducing projects')
    expect(rendered).to include('<b>Exciting news!</b>')
  end

  it 'strips out dangerous tags' do
    render_announcement
    expect(rendered).not_to include('<script>')
  end

  it 'uses an alert colour and class for the style' do
    announcement.update!(style: 'red')
    render_announcement
    expect(rendered).to include('alert-error')
    expect(rendered).to include('announcement--style-red')
  end
end

RSpec.describe 'alaveteli_pro/dashboard/_announcements', type: :view do
  let(:announcement) do
    FactoryBot.create(
      :announcement,
      rich_body: '<b>Exciting news!</b> <script>alert("!")</script>'
    )
  end

  before do
    controller.prepend_view_path(THEME_VIEWS)
    assign :user, FactoryBot.create(:pro_user)
    assign :announcements, [announcement]
  end

  it 'shows the announcement' do
    render template: 'alaveteli_pro/dashboard/_announcements'
    expect(rendered).to include('Introducing projects')
    expect(rendered).to include('<b>Exciting news!</b>')
  end

  it 'strips out dangerous tags' do
    render template: 'alaveteli_pro/dashboard/_announcements'
    expect(rendered).not_to include('<script>')
  end

  it 'adds a class for the style' do
    announcement.update!(style: 'blue')
    render template: 'alaveteli_pro/dashboard/_announcements'
    expect(rendered).to include('announcement--style-blue')
  end
end
