# frozen_string_literal: true

require 'help_page_history'

# Add a callback - to be executed before each request in development,
# and at startup in production - to patch existing app classes.
# Doing so in init/environment.rb wouldn't work in development, since
# classes are reloaded, but initialization is not run each time.
# See http://stackoverflow.com/questions/7072758/plugin-not-reloading-in-development-mode
#
Rails.configuration.to_prepare do
  HelpController.class_eval do
    before_action :set_history

    def house_rules; end

    private

    def set_history
      # Only set history if a template exists for this action
      template = lookup_context.find_template("#{controller_path}/#{action_name}")
      @history ||= HelpPageHistory.new(template)
    rescue ActionView::MissingTemplate
      # No template for this action, skip setting history
    end
  end

  # Live coupon price preview for the Pro plan signup page. Returns the
  # discounted price as JSON so alaveteli_pro/coupon_preview.js can update the
  # displayed amount before the user submits. Mirrors the access rules of
  # PlansController#show (login required, pro membership not) and skips
  # html_response so it can render JSON.
  AlaveteliPro::PlansController.class_eval do
    # raise: false so that an upstream rename of the html_response callback
    # degrades this action rather than failing to boot the whole application.
    skip_before_action :html_response, only: [:coupon_preview], raise: false
    before_action :authenticate, only: [:coupon_preview]

    def coupon_preview
      price = AlaveteliPro::Price.retrieve(params[:price_id])
      return render(json: { status: 'error' }, status: :not_found) unless price

      code = params[:coupon_code].to_s.strip

      # Only count attempts that actually reach Stripe. A blank code is answered
      # from the price alone, so it must not consume the user's allowance - the
      # field is cleared and retyped in the course of ordinary use.
      if code.present?
        if coupon_preview_rate_limiter.limit?(coupon_preview_rate_limit_id)
          return render(
            json: { status: 'error',
                    message: _('Too many attempts. Please try again later.') },
            status: :too_many_requests
          )
        end

        coupon_preview_rate_limiter.record!(coupon_preview_rate_limit_id)
      end

      render json: coupon_preview_json(price, code)
    end

    private

    # 30 coupon codes per user per hour: generous for somebody typing a code
    # they hold (the JS debounces, so one attempt is normally one request),
    # restrictive for anyone probing to find codes that exist. Built here rather
    # than held in a constant because this runs inside a to_prepare block, where
    # defining constants would be redefined on every reload in development.
    def coupon_preview_rate_limiter
      @coupon_preview_rate_limiter ||=
        AlaveteliRateLimiter::RateLimiter.new(
          AlaveteliRateLimiter::Rule.new(
            :coupon_preview, 30, AlaveteliRateLimiter::Window.new(1, :hour)
          )
        )
    end

    # Rate limit per user rather than per IP: the action requires a login, and
    # keying on IP would penalise everyone behind a shared address.
    def coupon_preview_rate_limit_id
      @user.id
    end

    def coupon_preview_json(price, code)
      return empty_preview(price) if code.blank?

      coupon = AlaveteliPro::Coupon.retrieve(code)

      # Existence is not validity: a coupon can exist in Stripe yet be rejected
      # at checkout (expired, max redemptions reached, etc). Mirror the two
      # failure messages SubscriptionsController#create surfaces.
      if coupon.nil?
        { status: 'invalid', message: _('Coupon code is invalid.') }
      elsif !coupon.valid
        { status: 'expired', message: _('Coupon code has expired.') }
      elsif mismatched_currency?(coupon)
        { status: 'invalid', message: _('Coupon code is invalid.') }
      elsif mismatched_interval?(price, coupon)
        { status: 'invalid',
          message: _('This coupon code cannot be used with this plan.') }
      else
        coupon_preview_payload(price, coupon)
      end
    end

    def empty_preview(price)
      {
        status: 'empty',
        amount: helpers.format_currency(
          price.unit_amount_with_tax, no_cents_if_whole: true
        )
      }
    end

    # An amount_off coupon only applies to a matching currency; Stripe would
    # reject a mismatch at checkout, so treat it as invalid rather than
    # previewing a bogus discount.
    def mismatched_currency?(coupon)
      coupon.amount_off && coupon.currency &&
        coupon.currency.downcase !=
          AlaveteliConfiguration.iso_currency_code.downcase
    end

    # A coupon can carry an `interval` metadata restriction (e.g. "month") to
    # limit it to a single billing interval. Stripe's coupon applies_to is
    # product-scoped only and can't distinguish the monthly price from the
    # annual price within the Pro product, so SubscriptionsController#create
    # enforces this restriction itself. The preview must refuse it too,
    # otherwise we'd advertise a discount that checkout then rejects.
    def mismatched_interval?(price, coupon)
      required = coupon.metadata.to_h[:interval]
      required.present? && required != price.recurring&.[]('interval')
    end

    # Replicates the arithmetic in
    # AlaveteliPro::Subscription::Discount#coupon_reduction (which mixes into a
    # Subscription and so can't be called against a bare Price + Coupon). That
    # method is the source of truth, and spec/coupon_preview_parity_spec.rb
    # asserts the two agree - if upstream changes, that spec fails rather than
    # this quietly drifting.
    #
    # Deliberately does NOT round the percent_off reduction: upstream's
    # coupon_reduction is a bare `plan.amount * coupon.percent_off / 100`. Real
    # Stripe returns a fractional percent_off (percent_off_precise), so rounding
    # here would show a price a cent away from the one the subscription page
    # displays after purchase.
    #
    # Tax matches Taxable#tax exactly: rounded VAT added to the unrounded net.
    # Kept separate from the formatting below so it can be compared directly
    # against upstream's figure in spec/coupon_preview_parity_spec.rb. Comparing
    # formatted strings would not do: format_currency rounds to the cent and
    # would mask a sub-cent divergence.
    def coupon_discounted_gross(price, coupon)
      net = price.unit_amount
      reduction = coupon.amount_off || (net * coupon.percent_off / 100)
      discounted_net = [net - reduction, 0].max
      tax_rate = AlaveteliConfiguration.stripe_tax_rate.to_f

      discounted_net + (discounted_net * tax_rate).round(0)
    end

    def coupon_preview_payload(price, coupon)
      discounted_gross = coupon_discounted_gross(price, coupon)
      saving = price.unit_amount_with_tax - discounted_gross

      {
        status: 'valid',
        amount: helpers.format_currency(
          discounted_gross, no_cents_if_whole: true
        ),
        original: helpers.format_currency(
          price.unit_amount_with_tax, no_cents_if_whole: true
        ),
        saving: coupon_saving_text(saving),
        terms: coupon_terms(coupon)
      }
    end

    def coupon_saving_text(saving)
      return if saving <= 0

      _('You save {{amount}}',
        amount: helpers.format_currency(saving, no_cents_if_whole: true))
    end

    # AlaveteliPro::Coupon#terms is metadata.humanized_terms || name, but both
    # accesses raise NoMethodError on the Stripe gem's StripeObject when the
    # attribute is absent. Read them defensively so an ordinary coupon (no
    # humanized_terms metadata, or a null name) can't 500 the preview.
    def coupon_terms(coupon)
      humanized = coupon.metadata.to_h[:humanized_terms]
      return humanized if humanized.present?

      coupon.name if coupon.respond_to?(:name)
    end
  end

  # Enforce coupon `interval` metadata restrictions at checkout. Stripe's
  # coupon applies_to is product-scoped only, so it can't stop a coupon meant
  # for a single interval (e.g. a monthly-only coupon) from discounting the
  # annual price within the same product. We block the mismatch here.
  #
  # This must halt via a before_action redirect rather than just setting
  # flash[:error]: SubscriptionsController#create runs its subscription-creating
  # block unconditionally and only checks flash[:error] afterwards, so a late
  # error would still charge the customer at full price before redirecting.
  AlaveteliPro::SubscriptionsController.class_eval do
    before_action :check_coupon_matches_price, only: [:create]

    private

    def check_coupon_matches_price
      return unless @coupon && @price

      required = @coupon.metadata.to_h[:interval]
      return if required.blank?
      return if required == @price.recurring&.[]('interval')

      flash[:error] = _('This coupon code cannot be used with this plan.')
      json_redirect_to plan_path(@price)
    end
  end
end
