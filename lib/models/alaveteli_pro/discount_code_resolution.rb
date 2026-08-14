# frozen_string_literal: true

module AlaveteliPro
  # Shared by the theme's patches to AlaveteliPro::PlansController and
  # AlaveteliPro::SubscriptionsController, so the coupon preview and the
  # checkout resolve a typed code - and judge whether it can be redeemed - in
  # exactly the same way. If the two diverge we advertise a discount that
  # checkout then refuses.
  module DiscountCodeResolution
    # Everything here is private: these are mixed into controllers, where a
    # public instance method would become an action.

    private

    # Coupon first, matching core's AlaveteliPro::SubscriptionsController
    # #load_coupon, then promotion code. Coupon ids are namespaced (a typed
    # FOO looks up RTK-FOO) while promotion codes are matched verbatim, so a
    # coupon RTK-FOO wins over a promotion code FOO. Documented in the README.
    def resolve_discount_code(code)
      AlaveteliPro::Coupon.retrieve(code) ||
        AlaveteliPro::PromotionCode.retrieve(code)
    end

    # Reasons a promotion code cannot be redeemed, so we can refuse before any
    # charge is attempted. Stripe would refuse most of these itself, but core's
    # SubscriptionsController#create only maps "No such coupon" and "Coupon
    # expired" to a useful message - anything else shows a generic payment
    # failure and emails an exception notification.
    #
    # Returns nil when the code is redeemable, or when it isn't a promotion
    # code at all.
    def promotion_code_error(discount, price)
      return unless discount.is_a?(AlaveteliPro::PromotionCode)

      if !discount.valid || discount.exhausted?
        _('Coupon code has expired.')
      elsif below_minimum_amount?(discount, price)
        _('This coupon code cannot be used with this plan.')
      elsif discount.first_time_transaction? && returning_customer?
        _('This coupon code is only available to new subscribers.')
      end
    end

    # A promotion code can require a minimum purchase. Verified against Stripe
    # test mode: it compares the minimum with the price *before* tax and
    # *before* the discount, and rejects the subscription outright if the price
    # falls short. A minimum in another currency can't be met at all.
    def below_minimum_amount?(discount, price)
      minimum = discount.minimum_amount
      return false if minimum.blank?

      currency = discount.minimum_amount_currency
      if currency.present? &&
         currency.downcase != AlaveteliConfiguration.iso_currency_code.downcase
        return true
      end

      price.unit_amount < minimum
    end

    # first_time_transaction is the one restriction we cannot read off the
    # promotion code, because it depends on the person's payment history. A
    # first-time subscriber has no Stripe customer yet - core's
    # SubscriptionsController#create builds it later - so they pass. Only
    # called for codes that actually carry the restriction.
    #
    # On a Stripe error, let them through: Stripe still enforces the
    # restriction when the subscription is created.
    def returning_customer?
      pro_account = current_user.pro_account
      return false unless pro_account

      pro_account.invoices.any?
    rescue Stripe::StripeError
      false
    end
  end
end
