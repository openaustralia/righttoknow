# frozen_string_literal: true

# Automatically mask Australian mobile phone numbers in published
# correspondence (issue #706).
#
# Registers a text mask via AlaveteliTextMasker.add_mask, the API upstream
# added in mysociety/alaveteli@34a3d7be2 (cherry-picked into our Alaveteli
# fork until it arrives in a tagged release). Text masks apply to text-type
# content only (message bodies, text and HTML attachments); PDFs and other
# binaries keep core's built-in email-only redaction. See "Australian mobile
# numbers are masked as text, not censored" in docs/DECISIONS.md for why.
#
# The pattern is deliberately tight (see the match/no-match table in
# spec/au_mobile_number_mask_spec.rb, which is the source of truth): a missed
# number can still be handled with a per-request censor rule, but an
# over-match silently corrupts the published record.
#
# Registered in after_initialize, not to_prepare: add_mask raises on
# duplicate names and to_prepare re-runs on every reload in development.
Rails.application.config.after_initialize do
  # The respond_to? guard lets this theme boot against a host Alaveteli that
  # predates the add_mask API (our fork gains it via cherry-pick; a tagged
  # release will follow). Remove the guard once the API is in a release the
  # fork has merged.
  if AlaveteliTextMasker.respond_to?(:add_mask)
    au_mobile_number = /
      (?<![\w-])                          # not inside a longer number, word or reference code
      (?:
        \+?61[ .-]?(?:\(0\)[ .-]?)?4      # international: +61 4..., 61 4..., +61 (0) 4...
        |
        04                                # domestic: 04...
      )
      \d{2}[ .-]?\d{3}[ .-]?\d{3}         # the remaining eight digits, standard groupings
      (?![\w-])                           # not running into more digits or letters
    /x

    AlaveteliTextMasker.add_mask(
      :au_mobile_number,
      pattern: au_mobile_number,
      replacement: "[#{_('mobile number')}]"
    )
  else
    Rails.logger.warn(
      'righttoknow theme: AlaveteliTextMasker.add_mask is unavailable in ' \
      'this Alaveteli version; Australian mobile numbers will not be masked'
    )
  end
end
