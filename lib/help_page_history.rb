class HelpPageHistory
  GITHUB_BASE =
    'https://github.com/openaustralia/righttoknow/commits/production'.freeze

  def initialize(template)
    @template = template
  end

  def commits_url
    template.inspect.gsub(/lib\/themes\/righttoknow/, GITHUB_BASE)
  end

  protected

  attr_reader :template
end
