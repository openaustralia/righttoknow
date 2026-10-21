# frozen_string_literal: true

# Announcement styles and rich text, backported from the unmerged upstream
# change https://github.com/mysociety/alaveteli/pull/9644 (commit 43206711).
#
# Once that is merged and released, and this theme is deployed on a release
# containing it, delete everything this change added: this file, its
# `require` in lib/alavetelitheme.rb, lib/helpers/announcement_style_helper.rb,
# the db/migrate directory and its path registration in lib/alavetelitheme.rb,
# the announcement views in lib/views, the AdminAnnouncementsController patch in
# lib/controller_patches.rb, the helper include in lib/helper_patches.rb, the
# announcement styles, and the specs. The migrations deliberately reuse the
# upstream class names and version numbers, so upstream's copies are skipped
# as already run. Upstream also drops `announcement_translations.content`,
# which this theme keeps, so follow up with a migration that drops it.
#
# Unlike upstream, `content` stays in the database. It still holds the text
# written before the move, and is no longer written to.
Rails.configuration.to_prepare do
  next if Announcement.translated_attribute_names.include?(:rich_body)

  Announcement.class_eval do
    translates :rich_body, touch: true
    delegate :rich_body=, :rich_body?, to: :translation
    after_save { translation.rich_body.save if translation.rich_body.changed? }
    translation_class.has_rich_text :rich_body

    cattr_accessor :style_labels,
                   instance_accessor: false,
                   default: {
                     'Default': 'default',
                     '🔴 Red': 'red',
                     '🟡 Yellow': 'yellow',
                     '🟢 Green': 'green',
                     '🔵 Blue': 'blue'
                   }

    # Declared so the app still boots before the migration has added the
    # column, which `rake db:migrate` needs in order to run at all.
    attribute :style, :string, default: 'default'
    enum :style, style_labels.values.index_by(&:itself),
         default: 'default',
         suffix: true

    validates :style, presence: true

    # Fall back to another locale's body, as Globalize does for the title
    def rich_body
      globalize_fallbacks(Globalize.locale).each do |locale|
        body = translation_for(locale, false)&.rich_body
        return body if body.present?
      end

      translation.rich_body
    end

    # The `content` column is legacy. Reading it from the rich body keeps core's
    # `validates :content, presence: true` meaning "has a body".
    def content
      rich_body.to_plain_text
    end
  end
end
