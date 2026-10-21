# frozen_string_literal: true

# Here you can override or add to the pages in the core website

Rails.application.routes.draw do
  # Additional help page example
  # get '/help/help_out' => 'help#help_out'
  get '/help/house_rules' => 'help#house_rules'

  # See lib/whatismyip_controller.rb. Controller 404s unless PROVIDE_WHATISMYIP is on.
  get '/whatismyip' => 'whatismyip#index'

  # We used to have a dedicated people page which was made in this theme.
  # Now that same information has been merged into the statistics page
  # in the main project there is no need for our version. Just to be
  # safe let's redirect the old url
  get '/people' => redirect('statistics#people')

  # Short, shareable donate link. Redirects to DONATION_URL (general.yml) with
  # UTMs attributing the visit to Right to Know. A 302 so browsers don't cache
  # the destination, which is expected to change. Incoming query parameters
  # are deliberately ignored. Not routed at all (404) if DONATION_URL is blank.
  get '/donate',
      to: redirect(status: 302) { DonationUrl.build(campaign: 'donate-redirect') },
      constraints: ->(_request) { AlaveteliConfiguration.donation_url.present? }

  # Live coupon price preview for the Pro plan signup page. Read-only JSON
  # endpoint (GET, no CSRF) consumed by alaveteli_pro/coupon_preview.js to show
  # the discounted price before the user submits. The action is added to
  # AlaveteliPro::PlansController in lib/controller_patches.rb. Gated by the
  # same pro_pricing feature flag as the plans pages it serves.
  constraints AlaveteliFeatures::Constraints::FeatureConstraint.new(:pro_pricing) do
    scope module: :alaveteli_pro do
      get 'plans/:price_id/coupon_preview',
          to: 'plans#coupon_preview',
          as: :plan_coupon_preview
    end
  end
end
