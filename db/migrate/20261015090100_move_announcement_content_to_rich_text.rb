# frozen_string_literal: true

# Backported from https://github.com/mysociety/alaveteli/pull/9644. The class
# name and version match upstream's so that, once upstream's copy arrives, it is
# skipped as already run.
#
# Unlike upstream's, this does not drop `announcement_translations.content`, so
# rolling back loses nothing, and it skips rows already copied so it is safe to
# run twice.
class MoveAnnouncementContentToRichText < ActiveRecord::Migration[8.0]
  RECORD_TYPE = 'Announcement::Translation'

  def up
    execute <<~SQL
      INSERT INTO action_text_rich_texts
        (name, body, record_type, record_id, created_at, updated_at)
      SELECT 'rich_body', t.content, '#{RECORD_TYPE}', t.id, NOW(), NOW()
      FROM announcement_translations t
      WHERE t.content IS NOT NULL AND t.content <> ''
        AND NOT EXISTS (
          SELECT 1 FROM action_text_rich_texts r
          WHERE r.record_type = '#{RECORD_TYPE}'
            AND r.record_id = t.id
            AND r.name = 'rich_body'
        )
    SQL
  end

  # Copies the current body back over `content`, including any edits made since
  # the move, before the rich text rows are removed.
  def down
    execute <<~SQL
      UPDATE announcement_translations t
      SET content = r.body
      FROM action_text_rich_texts r
      WHERE r.record_type = '#{RECORD_TYPE}'
        AND r.record_id = t.id
        AND r.name = 'rich_body'
    SQL

    execute <<~SQL
      DELETE FROM action_text_rich_texts
      WHERE record_type = '#{RECORD_TYPE}' AND name = 'rich_body'
    SQL
  end
end
