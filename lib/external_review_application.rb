# frozen_string_literal: true

# An application to a jurisdiction's external reviewer (for federal
# authorities, an Information Commissioner review by the Office of the
# Australian Information Commissioner under Part VII of the Freedom of
# Information Act 1982 (Cth)).
#
# The form collects structured answers instead of a free-form letter, and this
# object composes the public application letter from them. The contact fields
# (phone, previous OAIC reference, assistance needs) are "private details":
# they are appended to the email sent to the reviewer but never form part of
# the outgoing message body, so they are not published on the request page.
# See docs/DECISIONS.md ("External review applications are sent by email...").
class ExternalReviewApplication
  include ActiveModel::Model
  include Rails.application.routes.url_helpers
  include LinkToHelper

  # Needed for request_url in the letter, as OutgoingMessage does.
  default_url_options[:host] = AlaveteliConfiguration.domain

  DECISION_TYPES = %w[original internal_review no_decision].freeze

  # Direction as to certain procedures to be followed by applicants in
  # Information Commissioner reviews, 2.15: applications are due within 60
  # days of notification of a refusal decision.
  TIME_LIMIT_DAYS = 60

  attr_accessor :info_request, :decision_type, :decision_date, :disagreement,
                :phone, :oaic_reference, :assistance

  validates :decision_type,
            inclusion: {
              in: DECISION_TYPES,
              message: proc {
                _('Please choose which decision you are asking for a ' \
                  'review of')
              }
            }
  validates :disagreement,
            presence: {
              message: proc {
                _('Please explain which parts of the decision you disagree ' \
                  'with and why')
              }
            }
  validates :phone,
            presence: {
              message: proc {
                _('Please enter a contact telephone number (it will not be ' \
                  'published)')
              }
            }
  validate :decision_date_must_be_a_real_date, unless: :deemed_refusal?

  def deemed_refusal?
    decision_type == 'no_decision'
  end

  def parsed_decision_date
    return if decision_date.blank?

    Date.parse(decision_date.to_s)
  rescue ArgumentError, RangeError
    nil
  end

  # Soft warning only: late applications can still be accepted with an
  # extension of time under s 54T, so we warn rather than block.
  def outside_time_limit?
    return false if deemed_refusal?

    date = parsed_decision_date
    date.present? && date < TIME_LIMIT_DAYS.days.ago.to_date
  end

  # Details sent to the reviewer by email but never published. Also persisted
  # in the followup_sent event params so admins can see them if the
  # application needs to be resent.
  def private_details
    {
      phone: phone,
      oaic_reference: oaic_reference,
      assistance: assistance
    }.transform_values { |value| value.to_s.strip }.reject { |_, v| v.empty? }
  end

  # The public letter, composed entirely from the form answers. There is no
  # user-editable body: corrections happen by re-editing the form.
  def letter_body
    <<~BODY.strip
      Dear #{reviewer_name},

      I am applying for review by the Information Commissioner of a freedom of information decision of #{public_body_name} regarding my FOI request '#{info_request.title}'.

      #{decision_paragraph}

      #{disagreement.to_s.strip}

      A full history of my FOI request, including all correspondence and the decision I am seeking review of, is available on the Internet at this address: #{request_url(info_request)}

      Yours faithfully,

      #{info_request.user_name}
    BODY
  end

  private

  def reviewer_name
    reviewer = info_request.public_body.external_reviewer
    reviewer ? reviewer[:name] : _('the external reviewer')
  end

  def public_body_name
    info_request.public_body.name
  end

  def decision_paragraph
    case decision_type
    when 'original'
      _('I am seeking review of {{public_body_name}}\'s original decision, ' \
        'of which I was notified on {{decision_date}}.',
        public_body_name: public_body_name,
        decision_date: formatted_decision_date)
    when 'internal_review'
      _('I am seeking review of {{public_body_name}}\'s internal review ' \
        'decision, of which I was notified on {{decision_date}}.',
        public_body_name: public_body_name,
        decision_date: formatted_decision_date)
    when 'no_decision'
      _('{{public_body_name}} did not make a decision on my request within ' \
        'the time allowed by the Freedom of Information Act 1982, so I am ' \
        'seeking review of the deemed refusal of my request.',
        public_body_name: public_body_name)
    end
  end

  def formatted_decision_date
    date = parsed_decision_date
    date ? date.strftime('%-d %B %Y') : '[date]'
  end

  def decision_date_must_be_a_real_date
    return if parsed_decision_date

    errors.add(:decision_date,
               _('Please enter the date you were notified of the decision'))
  end
end
