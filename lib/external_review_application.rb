# frozen_string_literal: true

# An application to a jurisdiction's external reviewer (for federal
# authorities, an Information Commissioner review by the Office of the
# Australian Information Commissioner under Part VII of the Freedom of
# Information Act 1982 (Cth)).
#
# The form collects structured answers instead of a free-form letter, and this
# object composes the public application letter from them. The contact fields
# are "private details": they are appended to the email sent to the reviewer
# but never form part of the outgoing message body, so they are not published
# on the request page. See doc/adr/0005-external-review-applications-are-sent-by-email.md.
#
# Compliance with OAIC's "Direction as to certain procedures to be followed by
# applicants in Information Commissioner reviews" (26 June 2024, in effect
# from 1 July 2024). The form asks as few questions as the direction needs;
# everything else is derived from the request. Clause by clause:
#
#   2.7   in writing; "should" (not must) use the online form  - email, form linked as alternative
#   2.9a  applicant's name                                     - InfoRequest#user_name, private appendix
#   2.9b  contact telephone number                             - phone (required)
#   2.9c  email for correspondence                             - the request's own address, private appendix
#   2.10  preferred contact method                             - the request address, labelled as preferred
#   2.11a representative                                       - out of scope; form points at OAIC's own form
#   2.11b interpreter, 2.11c other assistance, 2.11d previous  - other_information (one optional field)
#         OAIC reference
#   2.12  identity may be queried                              - notice on the form (pseudonyms allowed here)
#   2.13  tell OAIC of contact detail changes                  - notice on the form
#   2.14  copy of the s 26 notice, or of the request           - ExternalReviewZip attached to the email
#   2.15a original / internal review / deemed refusal          - decision_type
#   2.15b date of decision; 60 days; s 54T reasons if late     - decision_date; extension_reasons
#                                                                (required only when late)
#   2.16  parts disputed, why, documents/exemptions, s 24AA    - disagreement (hint lists all four)
#   2.33  decisions published, individuals not named unless    - notice on the form
#         they ask
class ExternalReviewApplication
  include ActiveModel::Model
  include Rails.application.routes.url_helpers
  include LinkToHelper

  # Needed for request_url in the letter, as OutgoingMessage does.
  default_url_options[:host] = AlaveteliConfiguration.domain

  DECISION_TYPES = %w[original internal_review no_decision].freeze

  # Direction 2.15(b): applications are due within 60 days of notification of
  # an access refusal decision.
  TIME_LIMIT_DAYS = 60

  attr_accessor :info_request, :decision_type, :decision_date, :disagreement,
                :extension_reasons, :phone, :other_information

  # Names of attachments ExternalReviewZip left out of the correspondence copy
  # to fit the email size limit; set by ExternalReviewSender before the letter
  # is composed for sending, so the reviewer knows what to find at the URL.
  attr_writer :omitted_attachments

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
  validates :extension_reasons,
            presence: {
              message: proc {
                _('More than 60 days have passed since you were notified of ' \
                  'the decision, so please explain why it would be ' \
                  'reasonable to extend the time to apply')
              }
            },
            if: :outside_time_limit?

  def omitted_attachments
    @omitted_attachments || []
  end

  def deemed_refusal?
    decision_type == 'no_decision'
  end

  def parsed_decision_date
    return if decision_date.blank?

    Date.parse(decision_date.to_s)
  rescue ArgumentError, RangeError
    nil
  end

  # Direction 2.15(b): a late application needs reasons for an extension of
  # time under s 54T. The form asks for them only in this case.
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
      other_information: other_information
    }.transform_values { |value| value.to_s.strip }.reject { |_, v| v.empty? }
  end

  # The public letter, composed entirely from the form answers. There is no
  # user-editable body: corrections happen by re-editing the form.
  def letter_body
    ExternalReviewLetter.new(self).to_s
  end

  def reviewer_name
    reviewer = info_request.public_body.external_reviewer
    reviewer ? reviewer[:name] : _('the external reviewer')
  end

  def public_body_name
    info_request.public_body.name
  end

  def formatted_decision_date
    date = parsed_decision_date
    date ? date.strftime('%-d %B %Y') : '[date]'
  end

  private

  def decision_date_must_be_a_real_date
    return if parsed_decision_date

    errors.add(:decision_date,
               _('Please enter the date you were notified of the decision'))
  end
end

# Composes the public application letter from an ExternalReviewApplication,
# using the direction's own terms (s 26 notice, deemed access refusal).
class ExternalReviewLetter
  attr_reader :application

  delegate :info_request, :decision_type, :disagreement, :extension_reasons,
           :deemed_refusal?, :outside_time_limit?, :omitted_attachments,
           :reviewer_name, :public_body_name, :formatted_decision_date,
           to: :application

  def initialize(application)
    @application = application
  end

  def to_s
    [
      "Dear #{reviewer_name},",
      "I am applying for review by the Information Commissioner of a freedom of information decision of #{public_body_name} regarding my FOI request '#{info_request.title}'.",
      decision_paragraph,
      disagreement.to_s.strip,
      extension_paragraph,
      correspondence_paragraph,
      'Yours faithfully,',
      info_request.user_name
    ].compact.join("\n\n")
  end

  private

  def decision_paragraph
    case decision_type
    when 'original'
      _('I am seeking review of {{public_body_name}}\'s original decision ' \
        '(the s 26 notice), of which I was notified on {{decision_date}}.',
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
        'seeking review of the deemed access refusal.',
        public_body_name: public_body_name)
    end
  end

  # Direction 2.15(b): reasons for an extension of time under s 54T.
  def extension_paragraph
    return unless outside_time_limit? && extension_reasons.present?

    "#{_('This application is made more than 60 days after I was notified ' \
         'of the decision. I ask the Information Commissioner to extend ' \
         'the time to apply under s 54T of the FOI Act, for the following ' \
         'reasons:')}\n\n#{extension_reasons.to_s.strip}"
  end

  # Direction 2.14: a copy of the decision (or of the request, for a deemed
  # refusal) must accompany the application. The zip holds the whole
  # correspondence, so it covers both; the URL stays for anything left out
  # or arriving later.
  def correspondence_paragraph
    text = 'A copy of all correspondence on my FOI request, including the ' \
           "#{deemed_refusal? ? 'request' : 'decision I am seeking review of'}, " \
           'is attached to this email. The latest version, including any ' \
           'later correspondence, is available on the Internet at this ' \
           "address: #{application.request_url(info_request)}"
    return text if omitted_attachments.empty?

    "#{text}\n\nThe following attachments were too large to include in this " \
      "email and can be downloaded from that address: #{omitted_attachments.join(', ')}."
  end
end
