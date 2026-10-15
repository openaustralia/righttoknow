# frozen_string_literal: true

# Load our helpers
require 'helpers/alaveteli_pro/alternative_price_text_helper'
require 'helpers/announcement_style_helper'

Rails.configuration.to_prepare do
  ActionView::Base.include AlaveteliPro::AlternativePriceTextHelper
  ActionView::Base.include AnnouncementStyleHelper
end
