# frozen_string_literal: true

require 'ipaddr'
require 'net/http'

Rails.configuration.to_prepare do
  # Diagnostic for the nginx/Cloudflare real-IP trust boundary (see
  # ,plan-staging-rtk.md) - off by default since an open whoami would let
  # anyone check whether a forged CF-Connecting-IP is being trusted.
  # rubocop:disable Lint/ConstantDefinitionInBlock
  class WhoamiController < ApplicationController
    # rubocop:enable Lint/ConstantDefinitionInBlock
    skip_before_action :html_response
    before_action :check_enabled

    CLOUDFLARE_RANGE_URLS = [
      'https://www.cloudflare.com/ips-v4',
      'https://www.cloudflare.com/ips-v6'
    ].freeze

    def index
      ip = request.remote_ip
      ip += ' FAIL' if cloudflare_ip?(ip)
      render plain: ip
    end

    private

    def check_enabled
      head :not_found unless AlaveteliConfiguration.get('PROVIDE_WHOAMI', false)
    end

    def cloudflare_ip?(ip)
      cloudflare_ranges.any? { |range| range.include?(IPAddr.new(ip)) }
    rescue IPAddr::Error
      false
    end

    # Cached a day so this doesn't depend on cloudflare.com being reachable
    # on every check.
    def cloudflare_ranges
      cidrs = Rails.cache.fetch('whoami_cloudflare_ranges', expires_in: 1.day) do
        CLOUDFLARE_RANGE_URLS.flat_map do |url|
          Net::HTTP.get(URI(url)).lines.map(&:strip).reject(&:empty?)
        end
      end
      cidrs.map { |cidr| IPAddr.new(cidr) }
    end
  end
end
