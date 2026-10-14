# frozen_string_literal: true

# The correspondence copy attached to an external review application, which
# OAIC's procedure direction (2.14) requires. Built from the models with an
# Ability, like the host's InfoRequestBatchZip, so it also works from
# script/seed_test_data.rb. See lib/external_review_zip.rb.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)

RSpec.describe ExternalReviewZip do
  let(:user) { FactoryBot.create(:user) }
  let(:public_body) do
    FactoryBot.create(:public_body, name: 'Department of Examples',
                                    tag_string: 'federal')
  end
  let(:info_request) do
    FactoryBot.create(:info_request, public_body: public_body, user: user)
  end

  def add_response(attachments, prominence: 'normal')
    message = FactoryBot.create(:incoming_message,
                                info_request: info_request,
                                prominence: prominence,
                                foi_attachments_factories: attachments)
    info_request.log_event('response', incoming_message_id: message.id)
    message
  end

  def entries(data)
    files = {}
    Zip::File.open_buffer(StringIO.new(data)) do |zip|
      zip.entries.each { |e| files[e.name] = e.get_input_stream.read }
    end
    files
  end

  it 'holds a transcript and the document attachments, but no images' do
    add_response([[:pdf_attachment], [:jpeg_attachment]])

    result = described_class.new(info_request, ability: Ability.new(user)).build
    files = entries(result.data)

    expect(files.keys).to contain_exactly('correspondence.txt',
                                          '1_2_interesting.pdf')
    expect(files['correspondence.txt']).to include(info_request.title)
    expect(files['correspondence.txt']).to include('Attachment: interesting.pdf')
    expect(files['1_2_interesting.pdf']).to start_with('%PDF')
    expect(result.omitted).to be_empty
  end

  it "includes the applicant's requester_only messages but not for the public" do
    add_response([[:pdf_attachment]], prominence: 'requester_only')

    owner = entries(described_class.new(info_request, ability: Ability.new(user)).build.data)
    guest = entries(described_class.new(info_request, ability: Ability.guest).build.data)

    expect(owner.keys).to include('1_2_interesting.pdf')
    expect(guest.keys).to eq(['correspondence.txt'])
    expect(guest['correspondence.txt']).to include('This message has been hidden.')
  end

  it 'drops other documents before PDFs when over the size limit, and says so' do
    add_response([[:pdf_attachment], [:unknown_attachment]])
    # Real multi-megabyte fixtures would slow the suite for no gain; the
    # trimming order is what is under test.
    stub_const('ExternalReviewZip::MAX_BYTES', 1)

    result = described_class.new(info_request, ability: Ability.new(user)).build

    expect(entries(result.data).keys).to eq(['correspondence.txt'])
    expect(result.omitted).to eq(['1_3_interesting.spc', '1_2_interesting.pdf'])
  end
end

RSpec.describe ExternalReviewSender, 'with the correspondence zip' do
  let(:user) { FactoryBot.create(:user) }
  let(:public_body) do
    FactoryBot.create(:public_body, name: 'Department of Examples',
                                    tag_string: 'federal')
  end
  let(:info_request) do
    FactoryBot.create(:info_request, :with_incoming_with_pdf_attachment,
                      public_body: public_body, user: user)
  end
  let(:application) do
    ExternalReviewApplication.new(
      info_request: info_request,
      decision_type: 'original',
      decision_date: 10.days.ago.to_date.iso8601,
      disagreement: 'The section 47E exemption was wrongly applied.',
      phone: '0491 570 006'
    )
  end
  let(:outgoing_message) { described_class.build_outgoing_message(application) }
  let(:sender) { described_class.new(application, outgoing_message) }

  it 'attaches the zip to the application email and says so in the letter' do
    expect(sender.deliver).to be(true)

    mail = ActionMailer::Base.deliveries.last
    expect(mail.mime_type).to eq('multipart/mixed')
    zip = mail.attachments["#{info_request.url_title}.zip"]
    expect(zip).to be_present
    expect(zip.content_type).to start_with('application/zip')
    names = []
    Zip::File.open_buffer(StringIO.new(zip.body.decoded)) { |z| names = z.entries.map(&:name) }
    expect(names).to include('correspondence.txt', '1_2_interesting.pdf')
    expect(outgoing_message.reload.body)
      .to include('A copy of all correspondence on my FOI request')
    expect(mail.text_part.body.to_s).not_to include('zip')
  end

  it 'lists attachments left out to fit the size limit' do
    stub_const('ExternalReviewZip::MAX_BYTES', 1)

    sender.deliver

    expect(outgoing_message.reload.body)
      .to include('too large to include in this email')
    expect(outgoing_message.body).to include('1_2_interesting.pdf')
  end

  it 'saves nothing and raises when the zip cannot be built' do
    # The zip builder shells out to pdftk and reads ActiveStorage; the
    # failure under test is any of those going wrong.
    allow_any_instance_of(ExternalReviewZip).to receive(:build).and_raise(IOError)

    expect { sender.deliver }.to raise_error(ExternalReviewSender::ZipFailed)
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(info_request.reload.outgoing_messages.where(what_doing: 'external_review')).to be_empty
    expect(info_request.described_state).not_to eq('external_review')
  end
end
