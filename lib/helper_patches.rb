# Load our helpers
require 'helpers/alaveteli_pro/alternative_price_text_helper'

Rails.configuration.to_prepare do
  ActionView::Base.send(:include, AlaveteliPro::AlternativePriceTextHelper)
end
