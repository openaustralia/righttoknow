# frozen_string_literal: true

# Builds the donation URL with UTM parameters attributing the visit to Right to
# Know. The destination is the host's DONATION_URL setting (general.yml), so
# the Raisely address lives in one place. Used by the /donate redirect in
# lib/config/custom-routes.rb and by the donate links in the theme's views.
module DonationUrl
  UTM_SOURCE = 'righttoknow'
  UTM_MEDIUM = 'link'

  def self.build(campaign: 'donate-link', content: nil)
    uri = URI.parse(AlaveteliConfiguration.donation_url)
    utm = { utm_source: UTM_SOURCE,
            utm_medium: UTM_MEDIUM,
            utm_campaign: campaign,
            utm_content: content }.compact
    uri.query = URI.encode_www_form(URI.decode_www_form(uri.query.to_s) + utm.to_a)
    uri.to_s
  end
end
