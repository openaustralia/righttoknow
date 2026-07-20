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
    skip_before_action :html_response, only: [:coupon_preview]
    before_action :authenticate, only: [:coupon_preview]

    def coupon_preview
      price = AlaveteliPro::Price.retrieve(params[:price_id])
      return render(json: { status: 'error' }, status: :not_found) unless price

      render json: coupon_preview_json(price, params[:coupon_code].to_s.strip)
    end

    private

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

    # Replicates the arithmetic in
    # AlaveteliPro::Subscription::Discount#coupon_reduction (which mixes into a
    # Subscription and can't be called against a bare Price + Coupon). That
    # method is the source of truth; keep this in sync with it. Tax is applied
    # to the post-discount net, matching Taxable and the legacy tax_percent the
    # real subscription is created with.
    def coupon_preview_payload(price, coupon)
      net = price.unit_amount
      reduction = coupon.amount_off || (net * coupon.percent_off / 100).round
      discounted_net = [net - reduction, 0].max
      tax_rate = AlaveteliConfiguration.stripe_tax_rate.to_f
      discounted_gross = discounted_net + (discounted_net * tax_rate).round
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
end
