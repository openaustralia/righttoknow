# frozen_string_literal: true

module AlaveteliPro
  # A wrapper for a Stripe::PromotionCode that can stand in for an
  # AlaveteliPro::Coupon anywhere the Pro signup flow expects one.
  #
  # A promotion code is a customer-facing string pointing at a coupon, and it
  # carries the restrictions a coupon cannot express: a redemption cap per
  # code, first-time subscribers only, an expiry independent of the coupon's.
  # Stripe only enforces those if the subscription is created with
  # `promotion_code:`, which is why #id keeps returning the promotion code's
  # own id rather than the coupon's - see PromotionCodeSubscriptions, which
  # moves that id to the right Stripe parameter.
  #
  # Unlike coupon ids, promotion codes are not namespaced: the code is looked
  # up exactly as typed.
  class PromotionCode < SimpleDelegator
    # Marks an id as a promotion code's rather than a coupon's. It is a String
    # everywhere it matters - Stripe serialises it, specs compare it - but it
    # lets PromotionCodeSubscriptions route the id to the right Stripe
    # parameter without guessing from the id's format.
    class Id < String; end

    # The discount itself lives on the coupon behind the code. A promotion code
    # has no percent_off or amount_off of its own, so everything the price
    # arithmetic and the preview need has to come from the coupon.
    delegate :amount_off, :percent_off, :currency, :duration,
             :duration_in_months, to: :coupon

    # Filtering on active: true means an expired or exhausted code does not
    # resolve at all, and so reads as invalid rather than expired. That is the
    # right trade: Stripe only guarantees a code is unique amongst *active*
    # promotion codes, so dropping the filter could match a retired code that
    # shares its string with a live one.
    def self.retrieve(code)
      return if code.blank?

      promotion_code = Stripe::PromotionCode.list(
        code: code, active: true, limit: 1
      ).data.first
      return unless promotion_code

      # Resolve the coupon here rather than lazily, so a coupon we can't fetch
      # leaves us with nil - an invalid code - instead of raising later from
      # inside a before_action, where it would be a 500 rather than a message.
      new(promotion_code).tap(&:coupon)

    # Deliberately narrow, matching AlaveteliPro::Coupon.retrieve. Only
    # InvalidRequestError means "no such code"; a connection or rate limit
    # error means we don't know. Swallowing those would return nil, and core's
    # create only attaches a discount when one is present - so a Stripe blip
    # would quietly charge somebody full price instead of applying the code
    # they typed. Raising is the safer failure here.
    rescue Stripe::InvalidRequestError
      nil
    end

    def id
      Id.new(__getobj__.id)
    end

    def coupon
      @coupon ||= AlaveteliPro::Coupon.new(stripe_coupon)
    end

    def valid
      active && coupon.valid
    end

    # Restrictions live on the promotion code; the `interval` restriction and
    # `humanized_terms` live on the coupon. Merge the two so one coupon can
    # back several codes that describe themselves differently, with the code
    # winning.
    #
    # Returned as a StripeObject, not a Hash, so it behaves exactly like
    # AlaveteliPro::Coupon#metadata: callers reading `metadata.humanized_terms`
    # (as core's Coupon#terms does) work against either kind of discount, and
    # an absent key raises NoMethodError on both rather than only on one.
    def metadata
      Stripe::StripeObject.construct_from(
        coupon.metadata.to_h.merge(__getobj__.metadata.to_h)
      )
    end

    # Read defensively: Stripe omits the attribute rather than returning null,
    # and StripeObject raises NoMethodError for an absent attribute.
    def name
      coupon.name if coupon.respond_to?(:name)
    end

    # Mirrors AlaveteliPro::Coupon#terms, which is part of the interface this
    # class stands in for and is rendered by core's subscriptions view. Reads
    # the merged metadata rather than the coupon's, so a code can describe
    # itself differently from the coupon behind it.
    def terms
      metadata[:humanized_terms].presence || name
    end

    def exhausted?
      max_redemptions.present? && times_redeemed >= max_redemptions
    end

    def minimum_amount
      restrictions.to_h[:minimum_amount]
    end

    def minimum_amount_currency
      restrictions.to_h[:minimum_amount_currency]
    end

    def first_time_transaction?
      !!restrictions.to_h[:first_time_transaction]
    end

    def to_param
      code
    end

    private

    # Stripe returns the coupon expanded, but a bare id would put a String
    # behind the delegator and every discount attribute above would raise.
    def stripe_coupon
      stripe_coupon = __getobj__.coupon
      return stripe_coupon unless stripe_coupon.is_a?(String)

      Stripe::Coupon.retrieve(stripe_coupon)
    end
  end
end
