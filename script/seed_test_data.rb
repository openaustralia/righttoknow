# frozen_string_literal: true

# Seed a Right to Know test / development environment with a realistic subset
# of production data, fast.
#
# What it creates:
#   * A handful of REAL authorities for each state + federal jurisdiction tag,
#     taken from production's PUBLIC `all-authorities.csv` export. That export
#     contains only public information (name, tags, URL slug) - no request PII.
#   * Dummy requests per authority spread across a range of statuses and the
#     past 18 months, with fictional authority responses (some carrying PDF
#     decision letters) where the state implies one, and a subset of
#     authorities carrying 3+ "requester only" (prominence) requests.
#   * A fixed SHOWCASE of federal requests at each stage of the external
#     review process (refused, deemed refusal, under IC review, review
#     finished) plus one state request as a control, for demonstrating the
#     feature. See SHOWCASE below and "Trying external review locally" in
#     README.md.
#   * A browse-by-category taxonomy so the "View authorities" page groups the
#     seeded authorities. NOTE: production does not publish its category
#     definitions, so these categories are SYNTHESISED from the jurisdiction
#     tags on the imported authorities (one heading per jurisdiction, one
#     category per `<jurisdiction>` / `<jurisdiction>_*` tag actually present).
#     They are not a copy of production's own category structure.
#
# Authorities keep their real names, tags and URL slugs so jurisdiction logic
# and listings behave realistically, but every authority is given a DUMMY
# request email so this environment can never contact a real authority. All
# correspondence is fictional and says so.
#
# Every run is identical: the random number generator is seeded, so re-running
# after a database reset reproduces the same site.
#
# ---------------------------------------------------------------------------
# Run it against the Alaveteli APP (not this theme repo) via rails runner:
#
#   bundle exec rails runner \
#     ../alaveteli-themes/righttoknow/script/seed_test_data.rb
#
# or inside Docker:
#
#   docker compose run --rm app \
#     bundle exec rails runner \
#     alaveteli-themes/righttoknow/script/seed_test_data.rb
#
# Environment variables (all optional):
#   SEED_CSV_URL         Override the production CSV URL.
#   SEED_CSV_PATH        Read authorities from a local CSV instead of fetching
#                        (handy offline; expects the all-authorities.csv format).
#   SEED_BODIES_PER_TAG  Authorities per jurisdiction tag (default 5).
#   SEED_REBUILD_INDEX   Set to "1" to update the Xapian index at the end so
#                        seeded data shows up in search and request listings.
#   SEED_REPLACE         Set to "1" to destroy previously seeded requests first
#                        and recreate them (authorities, users and categories
#                        are kept). Without it, existing seeded requests are
#                        left alone.
#   SEED_SHOWCASE_BODY   URL name of the federal authority to put the external
#                        review showcase on (e.g. "abc"), if it is among the
#                        seeded authorities. Defaults to the first federal
#                        authority selected.
# ---------------------------------------------------------------------------

require 'csv'
require 'open-uri'
require 'active_support/testing/time_helpers'
require_relative 'seed_pdf'

# --- Safety -----------------------------------------------------------------
# This script fabricates data and rewrites authority request emails. It must
# never touch production.
#
# Note that this guard also rules out the STAGING server, not just production:
# both stages run with RAILS_ENV=production (the infrastructure repo installs a
# rails_env.rb that forces it), so Rails.env.production? is true on staging too.
# That is deliberate - the intended target is the local Docker development
# environment described in the README, not a deployed host.
abort 'Refusing to run in production: this seeds dummy data.' if Rails.env.production?

# Receiving a response emails the requester and sending an external review
# application emails the reviewer; neither should reach the mail catcher from
# a seed run. Delivery records are still written, since the mailer still runs.
ActionMailer::Base.perform_deliveries = false

# Records are created under travel_to so their timestamps, due dates and
# event history all fall on the intended past dates, instead of being
# backdated column by column afterwards.
CLOCK = Object.new.extend(ActiveSupport::Testing::TimeHelpers)

def travel_to(time, &block)
  CLOCK.travel_to(time, &block)
end

# Everything random here (states, topics, dates, prominences) comes from
# Kernel's RNG, so seeding it makes every run reproduce the same site.
srand(2026)

# --- Configuration ----------------------------------------------------------

# Jurisdiction tags recognised by the RTK theme (see lib/model_patches.rb).
JURISDICTION_TAGS = %w[federal ACT NSW NT QLD SA TAS VIC WA].freeze

# Human-readable heading titles for each jurisdiction, used when synthesising
# the browse-by-category taxonomy.
JURISDICTION_TITLES = {
  'federal' => 'Federal',
  'ACT' => 'Australian Capital Territory',
  'NSW' => 'New South Wales',
  'NT' => 'Northern Territory',
  'QLD' => 'Queensland',
  'SA' => 'South Australia',
  'TAS' => 'Tasmania',
  'VIC' => 'Victoria',
  'WA' => 'Western Australia'
}.freeze

# A body tag counts as a category tag if it is a jurisdiction tag or a
# jurisdiction-prefixed tag (e.g. NSW, NSW_state, federal_department). This
# deliberately excludes the grab-bag tags authorities also carry (foi_yes,
# directory_gov_au, police, ...).
CATEGORY_TAG_RE = /\A(#{JURISDICTION_TAGS.join('|')})(_.+)?\z/

# Authorities carrying any of these tags are skipped: they are not authorities
# a test environment should be filing requests against.
SKIP_TAGS = %w[defunct not_apply].freeze

BODIES_PER_TAG = Integer(ENV.fetch('SEED_BODIES_PER_TAG', 5))

CSV_URL = ENV.fetch(
  'SEED_CSV_URL',
  'https://www.righttoknow.org.au/body/all-authorities.csv'
)

# Any authority we create is given a request email at this domain so the test
# environment cannot email a real authority. example.com is reserved (RFC 2606).
DUMMY_EMAIL_DOMAIN = 'example.com'

EDITOR = 'seed_test_data.rb'
SEED_TITLE_PREFIX = 'SEED:'

# 0491 570 006 is one of ACMA's numbers reserved for fictional use.
FICTIONAL_PHONE = '0491 570 006'

# The states a dummy request can be left in. Weighted by repetition so the
# common cases (awaiting a response, successful) show up more often. All of
# these are exercised by the app's own factories, so they are safe to set
# directly. `transferred` is an RTK theme custom state and is added below only
# if the theme's custom states are loaded.
REQUEST_STATES = %w[
  waiting_response waiting_response waiting_response
  successful successful
  partially_successful
  rejected
  not_held
  waiting_clarification
  gone_postal
  internal_review
].freeze

# States that imply the authority wrote back, so the request gets a fictional
# response before it is classified. Those with a decision letter also get it
# as a PDF attachment.
RESPONDED_STATES = %w[
  successful partially_successful rejected not_held waiting_clarification
].freeze
LETTER_STATES = %w[successful partially_successful rejected].freeze

# Neutral, non-partisan dummy request topics.
REQUEST_TOPICS = [
  'Copies of internal policy documents',
  'Minutes of recent executive meetings',
  'Records of staff travel expenses',
  'Correspondence about the new IT system',
  'Statistics on complaints received this year',
  'The current organisational chart',
  'Contracts awarded to external consultants',
  'Briefing notes prepared for the Minister',
  'Register of gifts and hospitality',
  'Reports on building maintenance and safety'
].freeze

# The external review showcase: one request at each stage of the process, on
# the first federal authority (by URL name) the seed selects, plus a control on
# the first NSW authority to show nothing changes for other jurisdictions.
# Titles are fixed, without the SEED: prefix, so the pages read as real
# requests when demonstrated; the seed finds them again by title.
SHOWCASE = {
  refused: 'Briefing notes on the review of the records management policy',
  deemed_refusal: 'Register of consultancies engaged during 2025-26',
  under_review: 'Internal audit reports on IT system procurement',
  review_finished: 'Minutes of the executive board, January to March 2026',
  control: 'Copies of the current fleet vehicle policy'
}.freeze

# --- Loading the authority list --------------------------------------------

def load_authority_rows
  if (path = ENV['SEED_CSV_PATH'])
    puts "Reading authorities from local file: #{path}"
    CSV.read(path, headers: true)
  else
    puts "Fetching authorities from #{CSV_URL} ..."
    data = URI.parse(CSV_URL).open(&:read)
    CSV.parse(data, headers: true)
  end
rescue OpenURI::HTTPError, SocketError => e
  abort "Could not fetch the authority CSV (#{e.message}). " \
        'Provide a local copy with SEED_CSV_PATH=... instead.'
end

# Group authority rows by jurisdiction tag, then take a deterministic slice of
# each so re-runs pick the same authorities.
def select_authorities(rows)
  by_tag = Hash.new { |hash, key| hash[key] = [] }

  rows.each do |row|
    tags = row['Tags'].to_s.split(/\s+/)
    next if tags.intersect?(SKIP_TAGS)

    JURISDICTION_TAGS.each do |tag|
      by_tag[tag] << row if tags.include?(tag)
    end
  end

  JURISDICTION_TAGS.each_with_object({}) do |tag, selected|
    ranked = by_tag[tag].sort_by { |row| row['URL name'].to_s }
    selected[tag] = ranked.first(BODIES_PER_TAG)
    puts "  ! No authorities tagged '#{tag}' found in the CSV - skipping." if selected[tag].empty?
  end
end

# --- Creating records -------------------------------------------------------

def find_or_create_body(row)
  url_name = row['URL name'].to_s.strip
  return nil if url_name.empty?

  existing = PublicBody.find_by_url_name(url_name)
  return existing if existing

  PublicBody.create!(
    name: row['Name'],
    short_name: row['Short name'].to_s,
    url_name: url_name,
    request_email: "#{url_name}@#{DUMMY_EMAIL_DOMAIN}",
    tag_string: row['Tags'].to_s,
    last_edit_editor: EDITOR,
    last_edit_comment: 'Created by seed_test_data.rb'
  )
end

# The jurisdiction a category tag belongs to, or nil if it is not a category
# tag (see CATEGORY_TAG_RE).
def category_jurisdiction(tag)
  match = CATEGORY_TAG_RE.match(tag)
  match && match[1]
end

# A readable title for a synthesised category, e.g.
#   "NSW"                -> "New South Wales (all authorities)"
#   "NSW_state"          -> "New South Wales (state)"
#   "federal_department" -> "Federal (department)"
def category_title(tag, jurisdiction)
  full = JURISDICTION_TITLES[jurisdiction]
  suffix = tag[(jurisdiction.length + 1)..]
  suffix.blank? ? "#{full} (all authorities)" : "#{full} (#{suffix.tr('_', ' ')})"
end

# A description for a synthesised category. Categories must have one: the body
# page's `type_of_authority` helper calls `description.sub(...)` on it. E.g.
#   "NSW"                -> "New South Wales authority"
#   "NSW_state"          -> "New South Wales state authority"
#   "federal_department" -> "Federal department authority"
def category_description(tag, jurisdiction)
  full = JURISDICTION_TITLES[jurisdiction]
  suffix = tag[(jurisdiction.length + 1)..]
  suffix.blank? ? "#{full} authority" : "#{full} #{suffix.tr('_', ' ')} authority"
end

# Build the browse-by-category taxonomy from the category tags actually present
# on the seeded authorities. Additive and create-only: it appends under the
# existing PublicBody category root and never edits categories that already
# exist (which also side-steps the on-update tag-assignment validation).
def seed_categories(tags_by_jurisdiction)
  root = PublicBody.category_root
  created = { headings: 0, categories: 0 }

  JURISDICTION_TAGS.each do |jurisdiction|
    tags = tags_by_jurisdiction[jurisdiction]
    next if tags.empty?

    heading_title = JURISDICTION_TITLES[jurisdiction]
    heading = root.children.find_by(title: heading_title)
    unless heading
      heading = Category.create!(title: heading_title, parents: [root])
      created[:headings] += 1
    end

    tags.sort.each do |tag|
      next if Category.exists?(category_tag: tag)

      Category.create!(
        title: category_title(tag, jurisdiction),
        description: category_description(tag, jurisdiction),
        category_tag: tag,
        parents: [heading]
      )
      created[:categories] += 1
    end
  end

  created
end

def seed_users
  (1..5).map do |n|
    email = "seed_user_#{n}@#{DUMMY_EMAIL_DOMAIN}"
    User.find_by(email: email) || User.create!(
      name: "Seed Tester #{n}",
      email: email,
      password: 'seedpassword123',
      email_confirmed: true,
      receive_email_alerts: false
    )
  end
end

# Build the prominence for each of one authority's requests.
#
# Every third authority is made "requester only heavy": it gets at least 3
# requests fixed to the `requester_only` prominence, which is what the brief
# asks for. States are chosen separately at creation time.
def request_prominences(requester_heavy:)
  count = requester_heavy ? rand(4..8) : rand(3..8)

  Array.new(count) do |index|
    if requester_heavy && index < 3
      'requester_only'
    elsif rand < 0.1
      'backpage'
    else
      'normal'
    end
  end
end

# Create a request and record its initial message as sent at +sent_at+. Does
# NOT send a real email - it only writes the delivery record, which is also
# what sets the response due dates.
def create_request(body:, user:, title:, sent_at:, prominence: 'normal')
  travel_to(sent_at) do
    info_request = InfoRequest.create!(
      title: title,
      public_body: body,
      user: user,
      prominence: prominence
    )

    outgoing = info_request.outgoing_messages.create!(
      status: 'ready',
      message_type: 'initial_request',
      what_doing: 'normal_sort',
      body: "#{request_text(title)}\n\nYours faithfully,\n#{user.name}"
    )
    outgoing.record_email_delivery(
      body.request_email, "seed-#{info_request.id}@localhost"
    )

    info_request
  end
end

# Classify the request the way its owner would from the request page: a
# status_update event followed by the state change, so the history reads
# "classified as ..." rather than the state silently changing.
def classify(info_request, state, by:)
  info_request.log_event('status_update',
                         user_id: by.id,
                         old_described_state: info_request.described_state,
                         described_state: state)
  info_request.set_described_state(state, by)
end

# Deliver a fictional response into the request the way the mail pipeline
# would, so it gets a RawEmail, an IncomingMessage with parsed attachments,
# and a 'response' event, and shows up as correspondence on the request page.
# Attachments are [filename, binary content] pairs. The request is left
# awaiting classification, as a real response would leave it.
def receive_response(info_request, from:, subject:, text:, attachments: [])
  mail = Mail.new
  mail.to = info_request.incoming_email
  mail.from = from
  mail.subject = subject
  mail.date = Time.zone.now
  mail.body = text
  attachments.each do |filename, content|
    mail.add_file(filename: filename, content: content)
  end

  raw = mail.to_s
  info_request.receive(mail, raw, override_stop_new_responses: true)
  incoming = info_request.incoming_messages.reload.last
  incoming.parse_raw_email!
  incoming
end

# The sender a fictional authority response comes from. Reads the column
# directly: PublicBody#request_email returns the global override when
# OVERRIDE_ALL_PUBLIC_BODY_REQUEST_EMAILS is set, which is where outgoing
# mail should go, not where the authority's own mail appears to come from.
def authority_sender(body)
  "#{body.name.delete(',')} <#{body[:request_email]}>"
end

def long_date(time)
  time.strftime('%-d %B %Y')
end

# --- Fictional correspondence -----------------------------------------------
# All letters are fictional, name no officers, and say what they are. Section
# references appear only for federal authorities, where the seed knows the
# Act; other jurisdictions get the Act's name from the theme and generic
# wording, so nothing is made up about state legislation.

FICTIONAL_NOTE = 'This is a fictional letter generated by seed_test_data.rb ' \
                 'for a development environment. It does not reproduce any ' \
                 'real correspondence.'

def decision_outcome_paragraph(info_request, outcome)
  federal = info_request.public_body.jurisdiction == :federal
  case outcome
  when 'rejected'
    if federal
      'Searches identified 4 documents within the scope of your request. I ' \
        'have decided that each is conditionally exempt under section 47E(d) ' \
        'of the FOI Act, on the basis that disclosure would, or could ' \
        'reasonably be expected to, have a substantial adverse effect on the ' \
        'proper and efficient conduct of the operations of the agency, and ' \
        'that giving access at this time would, on balance, be contrary to ' \
        'the public interest. Access is refused.'
    else
      'Searches identified 4 documents within the scope of your request. I ' \
        'have decided that there is an overriding public interest against ' \
        'disclosure of each of them under the Act. Access is refused.'
    end
  when 'partially_successful'
    'Searches identified 6 documents within the scope of your request. I have ' \
      'decided to release 4 documents in full and 2 documents in part, with ' \
      'material that would unreasonably disclose personal information about ' \
      'third parties removed. The released material is attached.'
  else
    'Searches identified 3 documents within the scope of your request. I have ' \
      'decided to release all 3 documents in full. They are attached.'
  end
end

def review_rights_paragraph(info_request)
  if info_request.public_body.jurisdiction == :federal
    'You may apply for an internal review of this decision within 30 days ' \
      '(section 54B of the FOI Act). You may also apply to the Australian ' \
      'Information Commissioner for review of this decision within 60 days ' \
      '(section 54S), or make a complaint to the Information Commissioner ' \
      'about how your request was handled (section 70). There is no charge ' \
      'for either.'
  else
    'If you disagree with this decision you may apply for a review under ' \
      'the Act. Information about your review rights, including time ' \
      'limits, is available from the external reviewer for this jurisdiction.'
  end
end

def decision_letter(info_request, outcome:, decided_on:)
  body = info_request.public_body
  act = body.legislation.to_s(:act)
  <<~LETTER
    #{body.name}
    #{act} decision

    #{long_date(decided_on)}

    #{info_request.user_name}
    By email: #{info_request.incoming_email}

    Notice of decision - #{act}
    Our reference: FOI-#{info_request.id.to_s.rjust(4, '0')}

    Dear #{info_request.user_name},

    I refer to your request received on #{long_date(info_request.created_at)} for access to documents described as '#{info_request.title}'.

    I am an officer authorised to make decisions about access to documents under the #{act}. My decision is set out below.

    #{decision_outcome_paragraph(info_request, outcome)}

    #{review_rights_paragraph(info_request)}

    #{FICTIONAL_NOTE}

    Yours sincerely,

    Freedom of Information Officer
    #{body.name}
  LETTER
end

def released_documents(info_request)
  <<~DOCUMENT
    #{info_request.public_body.name}

    Documents released under #{info_request.public_body.legislation.to_s(:act)}
    In response to: '#{info_request.title}'

    Document 1 of 3 - Briefing note (extract)

    Purpose: To brief the executive on the matters raised in the request.

    Background: The agency reviews its arrangements in this area on a regular cycle. The most recent review considered current practice against the relevant policy and identified opportunities for improvement in record keeping and reporting.

    Recommendation: That the executive note the review's findings and agree to the proposed implementation timetable.

    Documents 2 and 3 - Meeting minutes (extracts)

    The committee noted the briefing and agreed to the recommendation. Action items were assigned and a progress report was requested for the following meeting.

    #{FICTIONAL_NOTE}
  DOCUMENT
end

def response_email_text(info_request, outcome)
  case outcome
  when 'not_held'
    "Dear #{info_request.user_name},\n\nI refer to your request for '#{info_request.title}'. " \
      'Searches of our records did not locate any documents within the scope ' \
      "of your request, and I am satisfied that no such documents exist.\n\n" \
      "#{FICTIONAL_NOTE}\n\nYours sincerely,\nFreedom of Information Officer\n" \
      "#{info_request.public_body.name}"
  when 'waiting_clarification'
    "Dear #{info_request.user_name},\n\nI refer to your request for '#{info_request.title}'. " \
      'The scope of your request is not clear enough for us to identify the ' \
      'documents you are seeking. Could you tell us the date range and the ' \
      "business area you are interested in?\n\n#{FICTIONAL_NOTE}\n\n" \
      "Yours sincerely,\nFreedom of Information Officer\n#{info_request.public_body.name}"
  else
    "Dear #{info_request.user_name},\n\nPlease find attached the notice of " \
      "decision on your request for '#{info_request.title}'.\n\n" \
      "#{FICTIONAL_NOTE}\n\nYours sincerely,\nFreedom of Information Officer\n" \
      "#{info_request.public_body.name}"
  end
end

# The authority's response to a request, matching the outcome it will be
# classified with. Decision letters arrive as PDFs; releases add a second PDF.
def receive_authority_response(info_request, outcome:)
  body = info_request.public_body
  attachments = []
  if LETTER_STATES.include?(outcome)
    attachments << ['notice-of-decision.pdf',
                    SeedPdf.render(decision_letter(info_request, outcome: outcome,
                                                                 decided_on: Time.zone.now))]
  end
  if %w[successful partially_successful].include?(outcome)
    attachments << ['released-documents.pdf',
                    SeedPdf.render(released_documents(info_request))]
  end

  receive_response(info_request,
                   from: authority_sender(body),
                   subject: "Re: #{info_request.legislation.to_s(:short)} request - #{info_request.title}",
                   text: response_email_text(info_request, outcome),
                   attachments: attachments)
end

# --- External review showcase -----------------------------------------------

def reviewer_sender(body)
  "#{reviewer_name(body)} <#{body.external_reviewer[:email]}>"
end

def reviewer_name(body)
  body.external_reviewer[:name]
end

# Send an IC review application through the same sender the site uses, so
# the seeded request is indistinguishable from one a person applied for:
# followup_sent event with the private appendix, censor rule for the phone
# number, and the external_review state.
def apply_for_external_review(info_request, decided_on:)
  application = ExternalReviewApplication.new(
    info_request: info_request,
    decision_type: 'original',
    decision_date: decided_on.to_date.iso8601,
    disagreement: 'The decision does not explain how disclosing the documents ' \
                  'could have a substantial adverse effect on the agency\'s ' \
                  'operations, and it does not weigh the public interest ' \
                  'factors in favour of disclosure. I ask the Information ' \
                  'Commissioner to review it.',
    phone: FICTIONAL_PHONE
  )
  raise "Seed application invalid: #{application.errors.full_messages.join(', ')}" unless application.valid?

  message = ExternalReviewSender.build_outgoing_message(application)
  raise 'Seed application failed to send' unless ExternalReviewSender.new(application, message).deliver

  message
end

def receive_reviewer_acknowledgement(info_request, reference:, decided_on:)
  body = info_request.public_body
  text = <<~TEXT
    Dear #{info_request.user_name},

    Thank you for your application for Information Commissioner review of the decision of #{body.name} dated #{long_date(decided_on)}.

    Our reference is #{reference}. Please quote it in any correspondence with us.

    We have notified #{body.name} that an application has been made and asked it to provide the documents at issue. We will contact you if we need further information from you. Information about how Information Commissioner reviews are conducted is available on our website.

    #{FICTIONAL_NOTE}

    Yours sincerely,

    Freedom of Information Regulatory Group
    #{reviewer_name(body)}
  TEXT

  receive_response(info_request,
                   from: reviewer_sender(body),
                   subject: "IC review application - #{reference} - #{info_request.title}",
                   text: text)
end

def receive_reviewer_decision(info_request, reference:, decided_on:)
  body = info_request.public_body
  letter = <<~LETTER
    #{reviewer_name(body)}

    Decision and reasons for decision

    Reference: #{reference}
    Applicant: #{info_request.user_name}
    Respondent: #{body.name}
    Decision date: #{long_date(Time.zone.now)}

    Decision

    Under section 55K of the Freedom of Information Act 1982, I set aside the decision of #{body.name} dated #{long_date(decided_on)} to refuse access under section 47E(d), and substitute a decision that the documents at issue are not conditionally exempt and that access is to be given to them.

    Reasons (summary)

    The respondent's submissions did not establish that disclosure of the documents could reasonably be expected to have a substantial adverse effect on the proper and efficient conduct of its operations. The documents are several years old, describe completed processes, and contain no material whose disclosure would prejudice current operations. It is therefore unnecessary to consider the public interest test.

    Review rights

    A party to this review may apply to the Administrative Review Tribunal for review of this decision.

    #{FICTIONAL_NOTE}

    Delegate of the Australian Information Commissioner
  LETTER

  text = "Dear #{info_request.user_name},\n\nPlease find attached the " \
         "Information Commissioner's decision on your review application " \
         "#{reference}. #{body.name} has been notified of the decision and " \
         "of its obligation to give effect to it.\n\n#{FICTIONAL_NOTE}\n\n" \
         "Yours sincerely,\n\nFreedom of Information Regulatory Group\n#{reviewer_name(body)}"

  receive_response(info_request,
                   from: reviewer_sender(body),
                   subject: "IC review decision - #{reference} - #{info_request.title}",
                   text: text,
                   attachments: [['ic-review-decision.pdf', SeedPdf.render(letter)]])
end

def receive_post_review_release(info_request, reference:)
  body = info_request.public_body
  text = "Dear #{info_request.user_name},\n\nFurther to the Information " \
         "Commissioner's decision in #{reference}, please find attached the " \
         "documents within the scope of your request, released in full.\n\n" \
         "#{FICTIONAL_NOTE}\n\nYours sincerely,\nFreedom of Information Officer\n#{body.name}"

  receive_response(info_request,
                   from: authority_sender(body),
                   subject: "Re: FOI request - #{info_request.title} - documents released",
                   text: text,
                   attachments: [['released-documents.pdf',
                                  SeedPdf.render(released_documents(info_request))]])
end

# The body of a seeded request. Background requests (titled "SEED: <topic> -
# <authority>") say plainly what they are; showcase requests read as real
# ones, asking for the documents their title names.
def request_text(title)
  if title.start_with?(SEED_TITLE_PREFIX)
    topic = title.delete_prefix(SEED_TITLE_PREFIX).split(' - ').first.strip
    "This is a dummy test request seeded for development.\n\n#{topic}."
  else
    "Dear Freedom of Information Officer,\n\nUnder the relevant freedom of " \
      'information legislation, I request access to the following documents: ' \
      "#{title.downcase}.\n\nI would prefer to receive the documents " \
      'electronically. If any part of my request is unclear, please contact me ' \
      'through this site so that I can clarify it.'
  end
end

# The stages of the showcase build on each other: every request starts as a
# refusal; the two under review add an application and the reviewer's
# acknowledgement; the finished one adds the reviewer's decision and the
# authority's release. Offsets are days before +now+, the real clock, so the
# demo pages show the same relative history on every rebuild.

def refused_request(body:, user:, title:, sent_at:, decided_on:)
  request = create_request(body: body, user: user, title: title, sent_at: sent_at)
  travel_to(decided_on) { receive_authority_response(request, outcome: 'rejected') }
  travel_to(decided_on + 1.day) { classify(request, 'rejected', by: user) }
  request
end

# Applied through the site, acknowledged a week later by the reviewer, then
# re-classified by the owner as still awaiting external review (the
# acknowledgement, like any response, leaves the request awaiting
# classification).
def put_under_review(request, user:, decided_on:, applied_on:, reference:)
  travel_to(applied_on) { apply_for_external_review(request, decided_on: decided_on) }
  travel_to(applied_on + 7.days) do
    receive_reviewer_acknowledgement(request, reference: reference, decided_on: decided_on)
  end
  travel_to(applied_on + 8.days) { classify(request, 'external_review', by: user) }
end

def finish_review(request, user:, decided_on:, reviewer_decided_on:, reference:)
  travel_to(reviewer_decided_on) do
    receive_reviewer_decision(request, reference: reference, decided_on: decided_on)
  end
  travel_to(reviewer_decided_on + 10.days) do
    receive_post_review_release(request, reference: reference)
  end
  travel_to(reviewer_decided_on + 11.days) { classify(request, 'successful', by: user) }
end

# One request at each stage of the external review process, skipping any that
# already exist.
def seed_showcase(federal_body:, control_body:, user:, now:)
  created = seed_showcase_pending(body: federal_body, user: user, now: now) +
            seed_showcase_reviewed(body: federal_body, user: user, now: now)

  # 5. Control: a refused state request, which gets no external review offer.
  if control_body && (title = new_showcase_title(:control))
    created << refused_request(body: control_body, user: user, title: title,
                               sent_at: now - 75.days, decided_on: now - 50.days)
  end

  created
end

# The two requests a demo applies from.
def seed_showcase_pending(body:, user:, now:)
  created = []

  # 1. Refused, within the 60 day window.
  if (title = new_showcase_title(:refused))
    created << refused_request(body: body, user: user, title: title,
                               sent_at: now - 75.days, decided_on: now - 50.days)
  end

  # 2. Deemed refusal: long overdue with no response, so the request page's
  #    banner offers external review instead of internal review.
  if (title = new_showcase_title(:deemed_refusal))
    created << create_request(body: body, user: user, title: title, sent_at: now - 75.days)
  end

  created
end

# The two requests showing what a review looks like once applied for.
def seed_showcase_reviewed(body:, user:, now:)
  created = []

  # 3. Under review.
  if (title = new_showcase_title(:under_review))
    decided_on = now - 105.days
    request = refused_request(body: body, user: user, title: title,
                              sent_at: now - 130.days, decided_on: decided_on)
    put_under_review(request, user: user, decided_on: decided_on,
                              applied_on: now - 95.days, reference: 'MR26/00123')
    created << request
  end

  # 4. Review finished: the reviewer set the refusal aside, the authority
  #    released the documents, and the owner classified the request successful.
  if (title = new_showcase_title(:review_finished))
    decided_on = now - 175.days
    request = refused_request(body: body, user: user, title: title,
                              sent_at: now - 200.days, decided_on: decided_on)
    put_under_review(request, user: user, decided_on: decided_on,
                              applied_on: now - 165.days, reference: 'MR26/00087')
    finish_review(request, user: user, decided_on: decided_on,
                           reviewer_decided_on: now - 40.days, reference: 'MR26/00087')
    created << request
  end

  created
end

# The showcase title for +key+ if that request doesn't exist yet, else nil.
def new_showcase_title(key)
  title = SHOWCASE.fetch(key)
  if InfoRequest.exists?(title: title)
    puts "  #{title} - already exists, leaving as is"
    return nil
  end
  title
end

# --- Run --------------------------------------------------------------------

now = Time.zone.now

# Include the theme's custom `transferred` state if it is loaded.
states = REQUEST_STATES.dup
if InfoRequest.respond_to?(:custom_states_loaded) &&
   InfoRequest.custom_states_loaded &&
   InfoRequest.theme_extra_states.include?('transferred')
  states << 'transferred'
end

if ENV['SEED_REPLACE'] == '1'
  seeded = InfoRequest.where('title LIKE ?', "#{SEED_TITLE_PREFIX}%")
                      .or(InfoRequest.where(title: SHOWCASE.values))
  puts "Destroying #{seeded.count} previously seeded requests ..."
  seeded.find_each(&:destroy)
end

rows = load_authority_rows
selection = select_authorities(rows)
users = seed_users

stats = {
  bodies_created: 0, bodies_existing: 0,
  requests_created: 0, requester_only: 0, responses: 0
}

user_cycle = users.cycle
body_index = 0

# Category tags found on the seeded authorities, grouped by jurisdiction, used
# to synthesise the browse-by-category taxonomy once seeding is done.
tags_by_jurisdiction = Hash.new { |hash, key| hash[key] = Set.new }

# The bodies the showcase goes on: first federal and first NSW selected,
# unless SEED_SHOWCASE_BODY names a different seeded federal authority.
showcase_bodies = {}
showcase_body_url_name = ENV['SEED_SHOWCASE_BODY']

selection.each do |tag, tag_rows|
  puts "\n== #{tag} (#{tag_rows.size} authorities) =="

  tag_rows.each do |row|
    body = find_or_create_body(row)
    next unless body

    if body.previously_new_record?
      stats[:bodies_created] += 1
    else
      stats[:bodies_existing] += 1
    end
    puts "  #{body.name} (#{body.url_name})"
    if tag == 'federal'
      showcase_bodies[tag] ||= body if showcase_body_url_name.nil?
      showcase_bodies[tag] = body if body.url_name == showcase_body_url_name
    elsif tag == 'NSW'
      showcase_bodies[tag] ||= body
    end

    body.tag_string.split(/\s+/).each do |body_tag|
      jurisdiction = category_jurisdiction(body_tag)
      tags_by_jurisdiction[jurisdiction] << body_tag if jurisdiction
    end

    # Idempotency: don't stack more seeded requests onto a body we've done.
    already_seeded = body.info_requests
                         .where('title LIKE ?', "#{SEED_TITLE_PREFIX}%").exists?
    if already_seeded
      puts '    already has seeded requests - leaving as is'
      body_index += 1
      next
    end

    requester_heavy = (body_index % 3 == 2)
    request_prominences(requester_heavy: requester_heavy).each do |prominence|
      state = states.sample
      topic = REQUEST_TOPICS.sample
      user = user_cycle.next
      sent_at = now - rand(20..540).days

      begin
        info_request = create_request(
          body: body,
          user: user,
          title: "#{SEED_TITLE_PREFIX} #{topic} - #{body.short_name.presence || body.name}",
          prominence: prominence,
          sent_at: sent_at
        )

        if RESPONDED_STATES.include?(state)
          responded_at = sent_at + rand(7..35).days
          travel_to(responded_at) { receive_authority_response(info_request, outcome: state) }
          travel_to(responded_at + 1.day) { classify(info_request, state, by: user) }
          stats[:responses] += 1
        elsif state != 'waiting_response'
          travel_to(sent_at + rand(7..35).days) { classify(info_request, state, by: user) }
        end
      rescue StandardError => e
        warn "    ! Skipped a request for #{body.url_name} " \
             "(state=#{state}): #{e.class}: #{e.message}"
        next
      end

      stats[:requests_created] += 1
      stats[:requester_only] += 1 if prominence == 'requester_only'
    end

    body_index += 1
  end
end

# --- External review showcase -----------------------------------------------
puts "\n== External review showcase =="
if showcase_bodies['federal']
  showcase = seed_showcase(federal_body: showcase_bodies['federal'],
                           control_body: showcase_bodies['NSW'],
                           user: users.first, now: now)
  showcase.each { |request| puts "  /request/#{request.url_title}" }
  stats[:requests_created] += showcase.size
else
  puts '  ! No federal authority selected for the showcase' \
       "#{" (SEED_SHOWCASE_BODY=#{showcase_body_url_name} not among the seeded authorities)" if showcase_body_url_name}."
end

# --- Browse-by-category taxonomy --------------------------------------------
puts "\nSynthesising browse categories from jurisdiction tags ..."
categories = seed_categories(tags_by_jurisdiction)
puts "  headings created:   #{categories[:headings]}"
puts "  categories created: #{categories[:categories]}"

# --- Xapian search index ----------------------------------------------------
# New PublicBody / InfoRequest records enqueue Xapian index jobs but do not
# appear in search or the main request listings until the index is updated.
if ENV['SEED_REBUILD_INDEX'] == '1'
  puts "\nUpdating Xapian index ..."
  begin
    ActsAsXapian.update_index(true, false)
    puts 'Xapian index updated.'
  rescue StandardError => e
    warn "Xapian update failed (#{e.message}). Run a full rebuild instead:"
    warn '  bundle exec rake xapian:destroy_and_rebuild_index ' \
         'models="PublicBody User InfoRequestEvent"'
  end
end

# --- Summary ----------------------------------------------------------------
puts "\n#{'-' * 60}"
puts 'Seeding complete.'
puts "  Authorities created:      #{stats[:bodies_created]}"
puts "  Authorities already there: #{stats[:bodies_existing]}"
puts "  Requests created:         #{stats[:requests_created]}"
puts "  ...of which requester_only: #{stats[:requester_only]}"
puts "  ...with authority responses: #{stats[:responses]}"
puts '-' * 60

unless ENV['SEED_REBUILD_INDEX'] == '1'
  puts <<~NEXT

    Authorities and the browse-by-category page work immediately (they are
    database-backed). Search and the request listings are Xapian-backed and
    will NOT show seeded data until the index is updated. Either re-run with
    SEED_REBUILD_INDEX=1, or run:

      bundle exec rake xapian:destroy_and_rebuild_index \\
        models="PublicBody User InfoRequestEvent"
  NEXT
end
