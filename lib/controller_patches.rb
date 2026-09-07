# frozen_string_literal: true

require 'help_page_history'
require 'models/alaveteli_pro/promotion_code'
require 'models/alaveteli_pro/discount_code_resolution'
require 'promotion_code_subscriptions'

# The external review application flow, entered from the ordinary followup
# URL with ?external_review=1 (mirroring core's ?internal_review=1). It reuses
# the followup machinery (preview, delivery, event logging) but:
#
# - the form is structured (ExternalReviewApplication) and the letter is
#   composed from it, so there is no editable message body;
# - the message goes to the jurisdiction's external reviewer
#   (PublicBody#external_reviewer), not the authority - see
#   ExternalReviewOutgoingMessage in model_patches.rb;
# - contact/assistance details are emailed but never published: they ride on
#   the outgoing message as a non-persisted attribute for the mailer view,
#   are recorded in the followup_sent event params for admins, and the phone
#   number gets a request-scoped censor rule as a safety net in case the
#   reviewer quotes it back in correspondence.
#
# Prepended so overridden actions can fall through to core with `super` for
# ordinary followups.
module ExternalReviewFollowups # rubocop:disable Metrics/ModuleLength
  def new
    return super unless @external_review

    render 'followups/external_review_new'
  end

  def preview
    return super unless @external_review

    @outgoing_message.info_request = @info_request
    if @external_review_application.valid? && @outgoing_message.valid?
      render 'followups/external_review_preview'
    else
      render 'followups/external_review_new'
    end
  end

  def create
    return super unless @external_review

    @outgoing_message.info_request = @info_request
    if !(@external_review_application.valid? && @outgoing_message.valid?)
      render 'followups/external_review_new'
    elsif @info_request.find_existing_outgoing_message(@outgoing_message.body)
      flash.clear
      flash[:error] = _('You previously submitted that exact external ' \
                        'review application for this request.')
      render 'followups/external_review_new'
    else
      send_external_review_application
      redirect_to request_url(@info_request)
    end
  end

  private

  # Runs before set_internal_review in the callback chain, so @external_review
  # isn't set yet - check the param directly. The check guards the validity of
  # the *authority's* address, which is irrelevant for an application sent to
  # the external reviewer (and would wrongly block review of e.g. a defunct
  # authority's decision).
  def check_incoming_message_can_be_followed_up
    return if params[:external_review]

    super
  end

  def set_internal_review
    super
    @external_review = false
    return unless params[:external_review]

    # Only jurisdictions with a wired-up external reviewer get this flow.
    raise ActiveRecord::RecordNotFound unless @info_request.public_body.external_reviewer

    @external_review = true
  end

  def check_reedit
    return super unless @external_review

    render 'followups/external_review_new' if params[:reedit]
  end

  def set_outgoing_message
    return super unless @external_review

    @external_review_application = ExternalReviewApplication.new(
      external_review_application_params.merge(info_request: @info_request)
    )
    @outgoing_message = OutgoingMessage.new(
      status: 'ready',
      message_type: 'followup',
      info_request_id: @info_request.id,
      what_doing: 'external_review',
      body: @external_review_application.letter_body
    )
    @outgoing_message.external_review_details =
      @external_review_application.private_details
  end

  def external_review_application_params
    return {} unless params[:external_review_application]

    params.require(:external_review_application)
          .permit(:decision_type, :decision_date, :disagreement,
                  :phone, :oaic_reference, :assistance).to_h
  end

  def send_external_review_application
    reviewer = @info_request.public_body.external_reviewer

    # OutgoingMailer.followup() depends on DB id of the
    # outgoing message, save just before sending.
    @outgoing_message.save!

    begin
      if @outgoing_message.sendable?
        mail_message = OutgoingMailer.followup(
          @outgoing_message.info_request, @outgoing_message, nil
        ).deliver_now
      end
    rescue *OutgoingMessage.expected_send_errors => e
      @outgoing_message.record_email_failure(e.message)
      flash[:error] = _('Your external review application has been saved ' \
                        'but not yet sent to {{reviewer_name}} due to an ' \
                        'error.',
                        reviewer_name: reviewer[:name])
    else
      @outgoing_message.record_email_delivery(
        mail_message.to_addrs.join(', '),
        mail_message.message_id
      )
      record_external_review_details
      create_external_review_censor_rule
      flash[:notice] = _('Your external review application has been sent ' \
                         'to {{reviewer_name}}.',
                         reviewer_name: reviewer[:name])
      @outgoing_message.info_request.reopen_to_new_responses
    ensure
      # Ensure DB is updated to isolate potential templating issues
      # from impacting delivery status information.
      @outgoing_message.save!
    end
  end

  # Keep the private details where admins can find them (e.g. to resend a
  # failed application), without them ever being rendered as correspondence.
  def record_external_review_details
    details = @external_review_application.private_details
    return if details.empty?

    event = @outgoing_message.info_request_events
                             .where(event_type: 'followup_sent').last
    return unless event

    event.params = event.params.merge(external_review_application: details)
    event.save!
  end

  # Belt and braces: the phone number is never in the public message body,
  # but the reviewer may quote it back in their correspondence, which arrives
  # into the public thread. A request-scoped censor rule redacts it on
  # display if that happens.
  def create_external_review_censor_rule
    phone = @external_review_application.private_details[:phone]
    return if phone.blank?
    return if @info_request.censor_rules.exists?(text: phone)

    rule = @info_request.censor_rules.create!(
      text: phone,
      replacement: _('[phone number]'),
      last_edit_editor: 'system',
      last_edit_comment: 'Added automatically when the external review ' \
                         "application in outgoing message ##{@outgoing_message.id} " \
                         'was sent, so the applicant\'s contact telephone ' \
                         'number is not published if quoted in correspondence'
    )
    rule.expire_requests
  end
end

# Add a callback - to be executed before each request in development,
# and at startup in production - to patch existing app classes.
# Doing so in init/environment.rb wouldn't work in development, since
# classes are reloaded, but initialization is not run each time.
# See http://stackoverflow.com/questions/7072758/plugin-not-reloading-in-development-mode
#
Rails.configuration.to_prepare do # rubocop:disable Metrics/BlockLength
  # Required here rather than at the top of the file: the class includes
  # LinkToHelper, which isn't autoloadable while the theme itself is being
  # required during initialization.
  require 'external_review_application'
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
    include AlaveteliPro::DiscountCodeResolution

    # raise: false so that an upstream rename of the html_response callback
    # degrades this action rather than failing to boot the whole application.
    skip_before_action :html_response, only: [:coupon_preview], raise: false

    # Registered under a theme-specific name, NOT `before_action :authenticate`:
    # re-registering a host callback by name replaces the host's registration
    # (ActiveSupport::Callbacks de-duplicates on the filter symbol), which
    # silently removed the login gate from #show and 500ed every logged-out
    # visitor there (issue #1055). Same hazard applies to any future theme
    # before_action that reuses a host callback name.
    before_action :authenticate_coupon_preview, only: [:coupon_preview]

    def authenticate_coupon_preview
      authenticate
    end

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

      coupon = resolve_discount_code(code)

      # Existence is not validity: a coupon can exist in Stripe yet be rejected
      # at checkout (expired, max redemptions reached, etc). Mirror the two
      # failure messages SubscriptionsController#create surfaces, and the
      # promotion code restrictions check_promotion_code_redeemable applies, so
      # the preview never advertises a discount checkout then refuses.
      if coupon.nil?
        { status: 'invalid', message: _('Coupon code is invalid.') }
      elsif !coupon.valid
        { status: 'expired', message: _('Coupon code has expired.') }
      elsif (message = promotion_code_error(coupon, price))
        { status: 'invalid', message: message }
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
    include AlaveteliPro::DiscountCodeResolution

    before_action :check_coupon_matches_price,
                  :check_promotion_code_redeemable, only: [:create]

    private

    # Accept a Stripe promotion code as well as a coupon id. Core's version
    # only tries AlaveteliPro::Coupon, which resolves a namespaced coupon id.
    def load_coupon
      @coupon = resolve_discount_code(params[:coupon_code])
    end

    def check_coupon_matches_price
      return unless @coupon && @price

      required = @coupon.metadata.to_h[:interval]
      return if required.blank?
      return if required == @price.recurring&.[]('interval')

      flash[:error] = _('This coupon code cannot be used with this plan.')
      json_redirect_to plan_path(@price)
    end

    # Refuse a promotion code Stripe would reject, for the same reason
    # check_coupon_matches_price halts here rather than setting flash[:error]
    # late: create runs its subscription-creating block unconditionally, so a
    # late error still charges the person at full price.
    #
    # A code exhausted between this check and the charge still falls through to
    # core's generic error. That race is rare and not worth guarding.
    def check_promotion_code_redeemable
      return unless @coupon && @price

      message = promotion_code_error(@coupon, @price)
      return unless message

      flash[:error] = message
      json_redirect_to plan_path(@price)
    end
  end

  AlaveteliPro::SubscriptionCollection.prepend(PromotionCodeSubscriptions)

  FollowupsController.prepend(ExternalReviewFollowups)
end
