# frozen_string_literal: true

require 'zip'

# The copy of the request's correspondence sent with an external review
# application, as a zip: a plain-text transcript plus the attachments. OAIC's
# procedure direction (2.7, 2.14) says a copy of the notice of decision, or of
# the FOI request for a deemed refusal, must be included; this is the same
# content the "Download a zip file of all correspondence" link gives the
# applicant, built from the models so it works outside a controller (the
# seed script uses it too). Prominence is honoured through the given Ability,
# so the applicant's own hidden messages are included and nobody else's are.
#
# Modelled on the host's InfoRequestBatchZip rather than on
# RequestController#make_request_zip, which is bound to a controller by can?
# and render_to_string.
class ExternalReviewZip
  # Above this, government mail gateways start bouncing. Attachments are
  # dropped by tier until the zip fits; the transcript always goes.
  MAX_BYTES = 15.megabytes

  TRANSCRIPT = 'correspondence.txt'

  # What a decision arrives as, in the order of how likely it is to matter.
  TIER_ONE_TYPES = %w[
    application/pdf
    application/vnd.ms-word
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/zip
  ].freeze

  # Images are signature logos and inline graphics far more often than they
  # are documents, and code can't tell which; anything relevant is still at
  # the request URL in the letter.
  EXCLUDED_TYPE_PREFIX = 'image/'

  Entry = Struct.new(:name, :body, :tier, keyword_init: true)

  # The zip bytes and the names of any attachments left out to fit.
  Result = Struct.new(:data, :omitted, keyword_init: true)

  attr_reader :info_request, :ability

  delegate :can?, to: :ability

  def initialize(info_request, ability:)
    @info_request = info_request
    @ability = ability
  end

  def build
    entries = attachment_entries
    omitted = []
    transcript = Entry.new(name: TRANSCRIPT, body: transcript_text, tier: 0)

    loop do
      data = write_zip([transcript] + entries)
      return Result.new(data: data, omitted: omitted) if data.bytesize <= MAX_BYTES || entries.empty?

      dropped = next_to_drop(entries)
      entries.delete(dropped)
      omitted << dropped.name
    end
  end

  def filename
    "#{info_request.url_title}.zip"
  end

  private

  # Drop the whole second tier first, largest first; then the largest of
  # the first tier.
  def next_to_drop(entries)
    tier_two = entries.select { |e| e.tier == 2 }
    (tier_two.presence || entries).max_by { |e| e.body.bytesize }
  end

  def write_zip(entries)
    buffer = Zip::OutputStream.write_buffer do |zip|
      entries.each do |entry|
        zip.put_next_entry(entry.name)
        zip.write(entry.body)
      end
    end
    buffer.string
  end

  def attachment_entries
    entries = []
    message_index = 0

    info_request.incoming_messages.each do |message|
      next unless can?(:read, message)

      message_index += 1
      message.get_attachments_for_display.each do |attachment|
        next unless can?(:read, attachment)
        next if attachment.content_type.to_s.start_with?(EXCLUDED_TYPE_PREFIX)

        entries << Entry.new(
          name: "#{message_index}_#{attachment.url_part_number}_#{attachment.display_filename}",
          body: message.apply_masks(attachment.default_body, attachment.content_type),
          tier: TIER_ONE_TYPES.include?(attachment.content_type) ? 1 : 2
        )
      end
    end

    entries
  end

  def transcript_text
    Transcript.new(info_request, ability: ability).to_s
  end
end

class ExternalReviewZip
  # The plain-text transcript in the zip, in the shape of the host's
  # request/show.text.erb but without the view context that template needs.
  class Transcript
    attr_reader :info_request, :ability

    delegate :can?, to: :ability

    def initialize(info_request, ability:)
      @info_request = info_request
      @ability = ability
    end

    def to_s
      lines = [
        'This is a plain-text version of the Freedom of Information request ' \
        "\"#{info_request.title}\". The latest, full version is available " \
        "online at #{request_url}.",
        ''
      ]

      info_request.info_request_events.each do |event|
        next unless event.visible

        section = transcript_section(event)
        next unless section

        lines << '-------------------------------'
        lines.concat(section)
        lines << ''
      end

      lines.join("\n")
    end

    private

    def transcript_section(event)
      case event.event_type
      when 'response'
        incoming_section(event.incoming_message)
      when 'sent', 'followup_sent'
        outgoing_section(event.outgoing_message, event)
      when 'resent', 'followup_resent'
        ["Date: #{format_date(event.created_at)}",
         "Sent #{event.outgoing_message.message_type == 'initial_request' ? 'request' : 'a follow up'} " \
         "to #{info_request.public_body.name} again."]
      when 'comment'
        comment = event.comment
        ["#{comment.user.name} left an annotation: (#{format_date(comment.created_at)})",
         comment.body.strip]
      end
    end

    def incoming_section(message)
      return [hidden_notice('message')] unless can?(:read, message)

      from = []
      from << message.safe_from_name if message.specific_from_name?
      from << info_request.public_body.name if message.from_public_body?

      lines = ["From: #{from.join(', ')}",
               "To: #{info_request.user_name || '[An anonymous user]'}",
               "Date: #{format_date(message.sent_at)}",
               '']
      lines << if can?(:read, message.get_main_body_text_part)
                 message.get_body_for_quoting
               else
                 hidden_notice('message')
               end
      message.get_attachments_for_display.each do |attachment|
        lines << if can?(:read, attachment)
                   "Attachment: #{attachment.display_filename} (#{attachment.display_size})"
                 else
                   "Attachment: #{hidden_notice('attachment')}"
                 end
      end
      lines
    end

    def outgoing_section(message, event)
      return [hidden_notice('message')] unless can?(:read, message)

      ["From: #{message.safe_from_name || '[An anonymous user]'}",
       "To: #{info_request.public_body.name}",
       "Date: #{format_date(event.created_at)}",
       '',
       message.get_body_for_text_display]
    end

    def hidden_notice(what)
      "This #{what} has been hidden."
    end

    def format_date(time)
      time.in_time_zone.to_date.strftime('%-d %B %Y')
    end

    def request_url
      "http://#{AlaveteliConfiguration.domain}/request/#{info_request.url_title}"
    end
  end
end
