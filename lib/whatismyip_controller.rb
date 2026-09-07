# frozen_string_literal: true

require 'ipaddr'
require 'net/http'

Rails.configuration.to_prepare do
  # In development ApplicationController is reloadable, so it is a brand-new
  # class object each time this block re-runs, while this hand-defined
  # constant (not managed by Zeitwerk) survives the reload still pointing at
  # the old one. Redefining would then raise "superclass mismatch", breaking
  # docker/setup's `db:migrate db:seed` and every dev reload (issue #1100),
  # so drop the stale constant first.
  Object.send(:remove_const, :WhatismyipController) if Object.const_defined?(:WhatismyipController, false)

  # Diagnostic for the nginx/Cloudflare real-IP trust boundary (see
  # ,plan-staging-rtk.md) - off by default since an open whatismyip would let
  # anyone check whether a forged CF-Connecting-IP is being trusted.
  # rubocop:disable Lint/ConstantDefinitionInBlock
  class WhatismyipController < ApplicationController
    # raise: false so that an upstream rename of the html_response callback
    # degrades this action rather than failing to boot the whole application.
    # rubocop:enable Lint/ConstantDefinitionInBlock
    skip_before_action :html_response, raise: false

    # Added protect_from_forgery since CodeQL complains and just in case we ever action a POST
    protect_from_forgery with: :exception
    before_action :check_enabled

    CLOUDFLARE_RANGE_URLS = %w[https://www.cloudflare.com/ips-v4 https://www.cloudflare.com/ips-v6].freeze

    # Real lists are ~15 (v4) and ~7 (v6) entries; anything under this is
    # Cloudflare erroring or truncating rather than a genuine empty list.
    MIN_EXPECTED_RANGES = 4

    # A short fetch timeout so a Cloudflare outage can not lock the Rails worker
    # as long as the default minute.
    # Failures are deliberately not cached, so this reduces the possible impact.
    # Issue: openaustralia/infrastructure#733
    FETCH_TIMEOUT = 5

    class RangesUnavailable < StandardError; end

    def index
      render plain: "#{request.remote_ip}#{status_suffix}"
    end

    private

    def check_enabled
      head :not_found unless AlaveteliConfiguration.get('PROVIDE_WHATISMYIP', false)
    end

    def status_suffix
      ip = IPAddr.new(request.remote_ip)
      cloudflare_ranges.any? { |range| range.include?(ip) } ? ' FAIL' : ''
    rescue RangesUnavailable, IPAddr::Error
      ' UNABLE TO CHECK'
    end

    # Return IPv4 and IPv6 cloudflare ranges as one array
    # Cached a day so this doesn't depend on cloudflare.com being reachable on
    # every check. Validated and parsed to IPAddr before caching, not after -
    # a failed/truncated fetch must raise inside the block so Rails.cache
    # never stores it, or a bad response would silently poison every check
    # for the next 24 hours (reported by Sentry as a real incident).
    def cloudflare_ranges
      Rails.cache.fetch('whatismyip_cloudflare_ranges', expires_in: 1.day) do
        CLOUDFLARE_RANGE_URLS.flat_map { |url| fetch_ranges(url) }
                             .map { |cidr| IPAddr.new(cidr) }
      end
    end

    # Fetch one range of ip addresses (IPv4 or IPv6)
    # Checked independently so one truncated list shouldn't pass
    # just because the other came back full-sized.
    # raises RangeUnavailable for network or content errors
    def fetch_ranges(url)
      response = fetch(URI(url))
      raise RangesUnavailable unless response.is_a?(Net::HTTPSuccess)

      ranges = response.body.lines.map(&:strip).reject(&:empty?)
      raise RangesUnavailable if ranges.size < MIN_EXPECTED_RANGES

      ranges
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, Net::ProtocolError,
           Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
      raise RangesUnavailable
    end

    # Fetch from uri with short open, read and write timeouts.
    # Throws Net::OpenTimeout, Net::ReadTimeout or Net::WriteTimeout, all of
    # which descend from Timeout::Error
    def fetch(uri)
      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: uri.scheme == 'https',
                      open_timeout: FETCH_TIMEOUT,
                      read_timeout: FETCH_TIMEOUT,
                      write_timeout: FETCH_TIMEOUT) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end
    end
  end
end
