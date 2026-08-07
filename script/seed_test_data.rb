# frozen_string_literal: true

# Seed a Right to Know test / development environment with a realistic subset
# of production data, fast.
#
# What it creates:
#   * A handful of REAL authorities for each state + federal jurisdiction tag,
#     taken from production's PUBLIC `all-authorities.csv` export. That export
#     contains only public information (name, tags, URL slug) - no request PII.
#   * Dummy requests per authority spread across a range of statuses, with a
#     subset of authorities carrying 3+ "requester only" (prominence) requests.
#   * A browse-by-category taxonomy so the "View authorities" page groups the
#     seeded authorities. NOTE: production does not publish its category
#     definitions, so these categories are SYNTHESISED from the jurisdiction
#     tags on the imported authorities (one heading per jurisdiction, one
#     category per `<jurisdiction>` / `<jurisdiction>_*` tag actually present).
#     They are not a copy of production's own category structure.
#
# Authorities keep their real names, tags and URL slugs so jurisdiction logic
# and listings behave realistically, but every authority is given a DUMMY
# request email so this environment can never contact a real authority.
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
# ---------------------------------------------------------------------------

require 'csv'
require 'open-uri'

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

def create_request(body:, user:, state:, prominence:, topic:)
  info_request = InfoRequest.create!(
    title: "#{SEED_TITLE_PREFIX} #{topic} - #{body.short_name.presence || body.name}",
    public_body: body,
    user: user,
    prominence: prominence
  )

  outgoing = info_request.outgoing_messages.create!(
    status: 'ready',
    message_type: 'initial_request',
    what_doing: 'normal_sort',
    body: "This is a dummy test request seeded for development.\n\n" \
          "#{topic}.\n\nYours faithfully,\n#{user.name}"
  )

  # Records the send (logs a 'sent' event + sets last_sent_at). Does NOT send
  # a real email - it only writes the delivery record.
  outgoing.record_email_delivery(
    body.request_email, "seed-#{info_request.id}@localhost"
  )

  # waiting_response is the default state, so only change it when needed.
  info_request.set_described_state(state) unless state == 'waiting_response'

  info_request
rescue StandardError => e
  warn "    ! Skipped a request for #{body.url_name} " \
       "(state=#{state}): #{e.class}: #{e.message}"
  nil
end

# --- Run --------------------------------------------------------------------

# Include the theme's custom `transferred` state if it is loaded.
states = REQUEST_STATES.dup
if InfoRequest.respond_to?(:custom_states_loaded) &&
   InfoRequest.custom_states_loaded &&
   InfoRequest.theme_extra_states.include?('transferred')
  states << 'transferred'
end

rows = load_authority_rows
selection = select_authorities(rows)
users = seed_users

stats = {
  bodies_created: 0, bodies_existing: 0,
  requests_created: 0, requester_only: 0
}

user_cycle = users.cycle
body_index = 0

# Category tags found on the seeded authorities, grouped by jurisdiction, used
# to synthesise the browse-by-category taxonomy once seeding is done.
tags_by_jurisdiction = Hash.new { |hash, key| hash[key] = Set.new }

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
      created = create_request(
        body: body,
        user: user_cycle.next,
        state: states.sample,
        prominence: prominence,
        topic: REQUEST_TOPICS.sample
      )
      next unless created

      stats[:requests_created] += 1
      stats[:requester_only] += 1 if prominence == 'requester_only'
    end

    body_index += 1
  end
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
