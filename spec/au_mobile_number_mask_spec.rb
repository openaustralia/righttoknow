# frozen_string_literal: true

# Exercises the Australian mobile number text mask registered by
# lib/text_mask_patches.rb (issue #706).
#
# This table of masked / not-masked examples is the source of truth for the
# pattern: the regex is whatever passes it. The pattern is deliberately tight
# (see docs/DECISIONS.md): a missed number can still be redacted with a
# per-request censor rule, but an over-match silently corrupts the published
# record, so the not-masked half of the table matters as much as the masked
# half.
#
# Mobile numbers here are ones ACMA reserves for fictional use (0491 570 1xx),
# and the landline is from the fictional (02) 5550 xxxx range, so no real
# person's number ever appears in this repo. The ABN is the Australian
# Taxation Office's own, a public agency identifier, not personal data.

# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper'))

describe 'Australian mobile number text mask' do
  def apply(text, content_type = 'text/plain')
    AlaveteliTextMasker.apply_masks(text.dup, content_type)
  end

  it 'is registered with the host masker' do
    expect(AlaveteliTextMasker.masks).to have_key(:au_mobile_number)
  end

  describe 'mobile number formats that are masked' do
    ['0491 570 156',
     '0491570156',
     '0491-570-156',
     '0491.570.156',
     '+61 491 570 156',
     '+61491570156',
     '61 491 570 156',
     '+61 (0) 491 570 156'].each do |number|
      it "masks #{number}" do
        expect(apply("Call me on #{number} after lunch."))
          .to eq('Call me on [mobile number] after lunch.')
      end
    end
  end

  describe 'digit strings that are not masked' do
    {
      'an eight digit local number' => 'Ring 5550 1234 for details.',
      'a landline with an area code' => 'Ring (02) 5550 1234 for details.',
      'an ABN' => 'Our ABN is 51 824 753 556.',
      'an ACN containing 04 after another digit' => 'ACN 004 000 000 applies.',
      'a hyphenated file reference' => 'See FOI-2026-0491570156 for details.',
      'a date' => 'Received on 04/12/2026 at noon.',
      'a dollar amount' => 'The contract cost $1,041,234,567.80 in total.',
      'a ten digit number not starting with 04' => 'Quote 0391 570 156 when replying.',
      'an eleven digit run starting with 0491' => 'Barcode 04915701567 was scanned.',
      'digits embedded in an alphanumeric reference' => 'See REF0491570156A for details.'
    }.each do |label, text|
      it "leaves #{label} alone" do
        expect(apply(text)).to eq(text)
      end
    end
  end

  # Text masks never reach the binary path (core's apply_binary_masks only
  # x's out email addresses and applies censor rules), so PDFs and other
  # binary attachments are deliberately unaffected by this mask. Guard that
  # boundary so a future change to it is a conscious one.
  it 'does not alter binary content' do
    binary = 'Call 0491 570 156 now'
    expect(apply(binary, 'application/octet-stream')).to eq(binary)
  end
end
