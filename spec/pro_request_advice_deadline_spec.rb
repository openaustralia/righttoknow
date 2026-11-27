# frozen_string_literal: true

# Guards the deadline sentence in the Pro "make a request" advice (issue
# #1170). The theme overrides the host's
# alaveteli_pro/info_requests/_new_request_advice partial so the sentence uses
# the chosen authority's own deadline and day basis (PublicBody#jurisdiction,
# reply_late_after_days and working_or_calendar_days in lib/model_patches.rb)
# instead of the site-wide default. The rest of the partial is unchanged, so
# those parts are asserted too, to catch the copy drifting from the host.
#
# View specs don't run the controller callback that puts the theme's views
# ahead of the host's, so the group does it itself; without it the host's
# partial renders and the deadline assertions fail.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)

RSpec.describe 'alaveteli_pro/info_requests/_new_request_advice', type: :view do
  before { controller.prepend_view_path(File.expand_path('../lib/views', __dir__)) }

  let(:neutral) do
    'Remember, public authorities have a legal deadline to respond to FOI ' \
    'requests. It depends on the authority.'
  end

  def render_advice(public_body: nil, batch: false)
    assign(:info_request, InfoRequest.new(public_body: public_body))
    assign(:info_request_batch, InfoRequestBatch.new) if batch
    render partial: 'alaveteli_pro/info_requests/new_request_advice'
    rendered
  end

  # The visible sentence only. The neutral wording is always present in the
  # data-neutral-text attribute, so assertions on the whole HTML can't tell
  # which sentence is showing.
  def deadline_text(html)
    Nokogiri::HTML.fragment(html).at_css('#js-advice-deadline').text.squish
  end

  def body_tagged(tag)
    FactoryBot.create(:public_body, tag_string: tag)
  end

  {
    'federal' => '30 calendar days',
    'ACT' => '30 calendar days',
    'NSW' => '20 working days',
    'NT' => '30 calendar days',
    'QLD' => '25 working days',
    'SA' => '30 calendar days',
    'TAS' => '20 working days',
    'VIC' => '45 calendar days',
    'WA' => '45 calendar days'
  }.each do |tag, expected|
    it "shows #{expected} for a #{tag} authority" do
      html = render_advice(public_body: body_tagged(tag))

      expect(deadline_text(html)).to eq(
        "Remember, this authority has #{expected} to respond to FOI requests."
      )
    end
  end

  it 'shows neutral wording for an authority with no jurisdiction tag' do
    html = render_advice(public_body: body_tagged('unrelated'))

    expect(deadline_text(html)).to eq(neutral)
  end

  it 'shows neutral wording when no authority has been chosen' do
    expect(deadline_text(render_advice)).to eq(neutral)
  end

  it 'shows neutral wording for a batch request even with a tagged authority' do
    html = render_advice(public_body: body_tagged('NSW'), batch: true)

    expect(deadline_text(html)).to eq(neutral)
  end

  it 'embeds the neutral wording for the script that resets it on change' do
    html = render_advice(public_body: body_tagged('NSW'))

    expect(html).to include('id="js-advice-deadline"')
    expect(html).to include(%(data-neutral-text="#{neutral}"))
  end

  it 'keeps the rest of the host advice' do
    html = render_advice(public_body: body_tagged('NSW'))

    expect(html).to include('Can I request information about myself?')
    expect(html).to include('click preview and send.')
    expect(html).to include('displayed publicly')
  end
end
