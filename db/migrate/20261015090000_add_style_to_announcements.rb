# frozen_string_literal: true

# Backported from https://github.com/mysociety/alaveteli/pull/9644. The class
# name and version match upstream's so that, once upstream's copy arrives, it is
# skipped as already run. Guarded so it is safe to run twice.
class AddStyleToAnnouncements < ActiveRecord::Migration[8.0]
  def change
    add_column :announcements, :style, :string,
               default: 'default', null: false, if_not_exists: true
  end
end
