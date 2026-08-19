# frozen_string_literal: true

# Sends a promotion code to Stripe as a promotion code.
#
# AlaveteliPro::SubscriptionsController#create writes the discount id under
# `coupon:` whatever it is, and we can't change core. A promotion code id has
# to reach Stripe as `promotion_code:` instead, so that Stripe applies the
# code, enforces its restrictions and counts the redemption - applying the
# underlying coupon directly would leave times_redeemed at zero and
# max_redemptions never counting down.
#
# The id gets there via #load_coupon in lib/controller_patches.rb, and carries
# AlaveteliPro::PromotionCode::Id so we don't have to guess its kind from the
# string.
module PromotionCodeSubscriptions
  def create(attributes = {})
    id = attributes[:coupon]
    return super unless id.is_a?(AlaveteliPro::PromotionCode::Id)

    super(attributes.except(:coupon).merge(promotion_code: id.to_s))
  end
end
