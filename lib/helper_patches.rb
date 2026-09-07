# frozen_string_literal: true

# Load our helpers
require 'helpers/alaveteli_pro/alternative_price_text_helper'

# Request status banner text for external review (see customstates.rb and
# ExternalReviewFollowups in controller_patches.rb). Prepended to the host's
# InfoRequestHelper (Ruby >= 3.0 propagates the prepend to everything that
# has already included it, including each controller's compiled _helpers
# module) so these definitions win and `super` reaches core. Including into
# ActionView::Base instead would lose: the per-controller _helpers module is
# included into the view class later, so core's methods would shadow ours.
module ExternalReviewInfoRequestHelper
  # Banner while a request sits in the theme's external_review state.
  # InfoRequestHelper#status_text dispatches on "status_text_#{status}".
  def status_text_external_review(info_request, _opts = {})
    reviewer = info_request.public_body.external_reviewer
    reviewer_name = reviewer ? reviewer[:name] : _('an external reviewer')
    _('This request is <strong>awaiting external review</strong> by ' \
      '{{reviewer_name}}.',
      reviewer_name: reviewer_name)
  end

  # For jurisdictions with a wired-up external reviewer, replace (not
  # supplement) core's "complain by requesting an internal review" advice on
  # long-overdue requests: the OAIC's procedure direction (2.15) says a
  # deemed refusal goes directly to Information Commissioner review, so
  # internal review is the wrong remedy here. Partially addresses #883 for
  # the federal slice.
  def status_text_waiting_response_very_overdue(info_request, opts = {})
    reviewer = info_request.public_body.external_reviewer
    return super unless reviewer

    str = _('Response to this request is <strong>long overdue</strong>.')
    str += ' '
    str += if info_request.public_body.not_subject_to_law?
             _('Although not legally required to do so, we would have ' \
                      'expected {{public_body_link}} to have responded by now',
               public_body_link: public_body_link(info_request.public_body))
           else
             _('By law, under all circumstances, {{public_body_link}} should ' \
                      'have responded by now',
               public_body_link: public_body_link(info_request.public_body))
           end
    str += ' '
    str += '('
    str += details_help_link(info_request.public_body)
    str += ').'

    unless info_request.is_external?
      str += ' '
      str += _('You can <strong>complain</strong> by')
      str += ' '
      str += link_to(
        _('applying to the {{reviewer_name}} for review of the deemed ' \
          'refusal of your request',
          reviewer_name: reviewer[:name]),
        new_request_followup_path(
          info_request.url_title, external_review: 1
        )
      )
      str += '.'
    end

    str
  end
end

Rails.configuration.to_prepare do
  ActionView::Base.include AlaveteliPro::AlternativePriceTextHelper
  InfoRequestHelper.prepend ExternalReviewInfoRequestHelper
end
