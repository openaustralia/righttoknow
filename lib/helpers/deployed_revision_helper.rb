# frozen_string_literal: true

# Reads the commits recorded at deploy time so /help/alaveteli can show what is
# running. Capistrano writes REVISION into each release for Alaveteli, and
# config/deploy.rb writes one into the theme after themes:install re-clones it.
module DeployedRevisionHelper
  ALAVETELI_REPO = 'openaustralia/alaveteli'
  THEME_REPO = 'openaustralia/righttoknow'
  FULL_SHA = /\A\h{40}\z/
  THEME_ROOT = File.expand_path('../..', __dir__)

  # The full commit hash from a REVISION file, or nil when the file is missing
  # or does not hold one (development, Docker and test have no REVISION).
  def deployed_revision(path)
    sha = File.read(path).strip
    sha if FULL_SHA.match?(sha)
  rescue SystemCallError
    nil
  end

  def alaveteli_revision
    deployed_revision(Rails.root.join('REVISION'))
  end

  def theme_revision
    deployed_revision(File.join(THEME_ROOT, 'REVISION'))
  end

  def deployed_revision_link(sha, repo)
    link_to sha[0, 7], "https://github.com/#{repo}/commit/#{sha}", title: sha
  end
end
