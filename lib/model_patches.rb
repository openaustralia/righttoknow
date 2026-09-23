# frozen_string_literal: true

# Add a callback - to be executed before each request in development,
# and at startup in production - to patch existing app classes.
# Doing so in init/environment.rb wouldn't work in development, since
# classes are reloaded, but initialization is not run each time.
# See http://stackoverflow.com/questions/7072758/plugin-not-reloading-in-development-mode
#
require_dependency 'legislation'

# Behaviour for outgoing messages whose what_doing is 'external_review': an
# application to the jurisdiction's external reviewer (see
# PublicBody#external_reviewer), sent from the request's address so the
# reviewer's correspondence threads back into the public request page.
# Prepended (rather than alias-chained) so reloading in development doesn't
# stack the patch.
module ExternalReviewOutgoingMessage
  # Contact and assistance details sent to the reviewer in the email but
  # never part of the public body text. Set by FollowupsController (see
  # controller_patches.rb) and read by the outgoing_mailer/followup view
  # override. Not persisted: the same details are recorded in the
  # followup_sent event params for admins.
  attr_accessor :external_review_details

  def external_review?
    message_type == 'followup' && what_doing == 'external_review'
  end

  # Applications go to the reviewer rather than the authority, so this
  # bypasses PublicBody#request_email and must apply the same
  # OVERRIDE_ALL_PUBLIC_BODY_REQUEST_EMAILS guard itself: on a development
  # or staging site every outgoing message is redirected, and an application
  # to a real Information Commissioner is the last thing that should escape.
  def to
    reviewer = external_review? && info_request.public_body.external_reviewer
    return super unless reviewer

    email = AlaveteliConfiguration.override_all_public_body_request_emails
    email = reviewer[:email] if email.blank?
    MailHandler.address_from_name_and_email(reviewer[:name], email)
  end

  def subject
    return super unless external_review?

    _('Information Commissioner review application: {{request_title}} ' \
      '({{public_body_name}})',
      request_title: info_request.title,
      public_body_name: info_request.public_body.name)
  end

  private

  def set_info_request_described_state
    super
    return unless status == 'sent' && external_review?

    info_request.set_described_state('external_review')
  end
end

# Attaches the correspondence zip (ExternalReviewZip) to an external review
# application email. The zip travels on external_review_details[:zip], set by
# ExternalReviewSender, so ordinary followups are untouched. Attachments must
# be added before mail() runs, hence before super.
module ExternalReviewOutgoingMailer
  def followup(info_request, outgoing_message, incoming_message_followup)
    zip = outgoing_message.try(:external_review_details).try(:[], :zip)
    if outgoing_message.try(:external_review?) && zip
      attachments[zip[:filename]] = { content_type: 'application/zip',
                                      content: zip[:data] }
    end

    super
  end
end

Legislation.class_eval do
  def self.all
    [
      new(
        key: 'foi',
        short: _('FOI'),
        full: _('Freedom of Information'),
        with_a: _('A Freedom of Information request'),
        act: _('Freedom of Information Act'),
        refusals: refusals['foi']
      ),
      new(
        key: 'eir',
        short: _('EIR'),
        full: _('Environmental Information Regulations'),
        with_a: _('An Environmental Information request'),
        act: _('Environmental Information Regulations'),
        refusals: refusals['eir']
      ),
      new(
        key: 'gipa',
        short: _('GIPA'),
        full: _('Government Information (Public Access)'),
        with_a: _('A Government Information (Public Access) request'),
        act: _('Government Information (Public Access) Act'),
        refusals: refusals['gipa'] || []
      ),
      new(
        key: 'rti',
        short: _('RTI'),
        full: _('Right to Information'),
        with_a: _('A Right to Information request'),
        act: _('Right to Information Act'),
        refusals: refusals['rti'] || []
      )
    ]
  end
end

Rails.configuration.to_prepare do
  PublicBody.class_eval do
    def jurisdiction
      if has_tag?('ACT')
        :act
      elsif has_tag?('NSW')
        :nsw
      elsif has_tag?('NT')
        :nt
      elsif has_tag?('QLD')
        :qld
      elsif has_tag?('SA')
        :sa
      elsif has_tag?('TAS')
        :tas
      elsif has_tag?('VIC')
        :vic
      elsif has_tag?('WA')
        :wa
      elsif has_tag?('federal')
        :federal
      end
    end

    def reply_late_after_days
      case jurisdiction
      when :nsw, :tas
        20
      when :qld
        25
      when :federal, :act, :nt, :sa
        30
      when :vic, :wa
        45
      else
        AlaveteliConfiguration.reply_late_after_days
      end
    end

    def working_or_calendar_days
      case jurisdiction
      when :nsw, :tas, :qld
        'working'
      else
        'calendar'
      end
    end

    def info_requests_hidden_count
      info_requests.where('prominence != ?', 'normal').count
    end

    # The body that conducts external (merits) review of FOI decisions in
    # this authority's jurisdiction, or nil where we don't (yet) support
    # applying for external review through the site. Only federal is wired
    # up so far; other jurisdictions are tracked in issue #875. The
    # application is sent by email (the OAIC's procedure direction says
    # applications *should*, not must, use its online form), with the online
    # form linked as an alternative.
    #
    # The reviewer table lives here in code, not in general.yml: the host's
    # EXTERNAL_REVIEWERS setting is a single string, which can't express one
    # reviewer per jurisdiction, and nothing in the host reads it anyway. It
    # is deliberately left unused (see ADR-0005 and issue #752).
    def external_reviewer
      case jurisdiction
      when :federal
        {
          name: 'Office of the Australian Information Commissioner',
          email: 'FOIDR@oaic.gov.au',
          form_url: 'https://webform.oaic.gov.au/prod?entitytype=ICReview&layoutcode=ICReviewWF'
        }
      end
    end
  end

  PublicBody.class_eval do
    def legislation
      case jurisdiction
      when :nsw
        Legislation.find!('gipa')
      when :qld, :tas
        Legislation.find!('rti')
      else
        Legislation.find!('foi')
      end
    end
  end

  InfoRequest.class_eval do
    # Make the due date stored by the host's set_due_dates jurisdiction-aware.
    # The host's version uses the site-wide reply_late_after_days config; ours
    # comes from the public body's jurisdiction tag (see PublicBody patches
    # above). The host calls this whenever an event resets due dates, and
    # stores the result in the date_response_required_by column.
    def calculate_date_response_required_by
      Holiday.due_date_from(date_initial_request_last_sent_at, public_body.reply_late_after_days,
                            public_body.working_or_calendar_days)
    end

    # Prefer the stored column, computing only as a fallback, exactly like the
    # host's own reader. From 2015 to 2026 this theme overrode the reader to
    # always recompute (the column didn't exist when the override was written),
    # which made InfoRequest#calculate_status - and any page rendering it, like
    # /list - slow enough that the status had to be hidden. Stored values are
    # kept jurisdiction-correct by the calculate_date_response_required_by
    # override; script/populate_due_dates.rb backfills requests stored before
    # that override existed (re-run it if a body changes jurisdiction tag).
    def date_response_required_by
      date = read_attribute(:date_response_required_by)
      return date if date

      calculate_date_response_required_by
    end
  end

  OutgoingMessage.prepend ExternalReviewOutgoingMessage
  OutgoingMailer.prepend ExternalReviewOutgoingMailer
end
