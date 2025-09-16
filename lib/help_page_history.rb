class HelpPageHistory
  GITHUB_BASE =
    'https://github.com/openaustralia/righttoknow/commits/production'.freeze

  def initialize(template)
    @template = template
  end

  def commits_url
    # Use the template identifier (full path) and replace the local path prefix with the GitHub base URL
    path = template.identifier
    filename = File.basename(path)
   # Build the GitHub commits URL for this file
   "#{GITHUB_BASE}/lib/views/help/#{filename}"
  end

  protected

  attr_reader :template
end
