# frozen_string_literal: true

# Sends a composed ExternalReviewApplication to the jurisdiction's external
# reviewer and records everything the send leaves behind: the delivery (or
# failure) on the outgoing message, the private details in the event params
# for admins, and the censor rule that keeps the phone number out of the
# public thread if the reviewer quotes it back.
#
# Shared by FollowupsController (see ExternalReviewFollowups in
# controller_patches.rb) and script/seed_test_data.rb, so a seeded request
# under external review is indistinguishable from one a person applied for.
# Flash messages stay with the controller; this class only reports whether
# the send succeeded.
class ExternalReviewSender
  # The public outgoing message for an application: a followup whose
  # what_doing is 'external_review', so ExternalReviewOutgoingMessage routes
  # it to the reviewer and moves the request into the external_review state
  # once sent. The private details ride along as a non-persisted attribute
  # for the outgoing_mailer/followup view override.
  def self.build_outgoing_message(application)
    message = OutgoingMessage.new(
      status: 'ready',
      message_type: 'followup',
      info_request_id: application.info_request.id,
      what_doing: 'external_review',
      body: application.letter_body
    )
    message.external_review_details = application.private_details
    message
  end

  attr_reader :application, :outgoing_message

  def initialize(application, outgoing_message)
    @application = application
    @outgoing_message = outgoing_message
  end

  # Raised when the correspondence copy the direction requires (2.14) can't
  # be built. Nothing is saved: a knowingly incomplete application should not
  # go out silently, and the applicant can use the reviewer's own form.
  class ZipFailed < StandardError; end

  # Returns true when the application was sent, false when delivery raised one
  # of OutgoingMessage.expected_send_errors (recorded as a send_error event,
  # with the private details kept so an admin can resend). Raises ZipFailed
  # if the correspondence zip could not be built.
  def deliver
    attach_correspondence_zip

    # OutgoingMailer.followup() depends on DB id of the
    # outgoing message, save just before sending.
    outgoing_message.save!

    begin
      if outgoing_message.sendable?
        mail_message = OutgoingMailer.followup(
          info_request, outgoing_message, nil
        ).deliver_now
      end
    rescue *OutgoingMessage.expected_send_errors => e
      outgoing_message.record_email_failure(e.message)
      record_private_details
      false
    else
      outgoing_message.record_email_delivery(
        mail_message.to_addrs.join(', '),
        mail_message.message_id
      )
      record_private_details
      create_censor_rule
      info_request.reopen_to_new_responses
      true
    ensure
      # Ensure DB is updated to isolate potential templating issues
      # from impacting delivery status information.
      outgoing_message.save!
    end
  end

  private

  def info_request
    outgoing_message.info_request
  end

  # The applicant's own view of the request (Ability.new(user)), so a
  # decision they have hidden from the public still reaches the reviewer.
  # Files left out to fit MAX_BYTES are listed in the letter, which is why
  # the letter body is composed here rather than earlier.
  def attach_correspondence_zip
    zip = ExternalReviewZip.new(info_request, ability: Ability.new(info_request.user))
    result = zip.build
    application.omitted_attachments = result.omitted
    outgoing_message.body = application.letter_body
    outgoing_message.external_review_details =
      application.private_details.merge(zip: { filename: zip.filename, data: result.data })
  rescue StandardError => e
    raise ZipFailed, "#{e.class}: #{e.message}"
  end

  # Keep the private details where admins can find them (e.g. to resend a
  # failed application), without them ever being rendered as correspondence.
  # On success they ride on the followup_sent event; on failure, the
  # send_error event, so nothing is lost if the send needs retrying.
  def record_private_details
    details = application.private_details
    return if details.empty?

    event = outgoing_message.info_request_events
                            .where(event_type: %w[followup_sent send_error]).last
    return unless event

    event.params = event.params.merge(external_review_application: details)
    event.save!
  end

  # Belt and braces: the phone number is never in the public message body,
  # but the reviewer may quote it back in their correspondence, which arrives
  # into the public thread. A request-scoped censor rule redacts it on
  # display if that happens.
  def create_censor_rule
    phone = application.private_details[:phone]
    return if phone.blank?
    return if info_request.censor_rules.exists?(text: phone)

    rule = info_request.censor_rules.create!(
      text: phone,
      replacement: _('[phone number]'),
      last_edit_editor: 'system',
      last_edit_comment: 'Added automatically when the external review ' \
                         "application in outgoing message ##{outgoing_message.id} " \
                         'was sent, so the applicant\'s contact telephone ' \
                         'number is not published if quoted in correspondence'
    )
    rule.expire_requests
  end
end
