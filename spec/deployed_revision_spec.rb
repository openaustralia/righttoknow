# frozen_string_literal: true

# Covers the deployed commit lines on /help/alaveteli: the helper in
# lib/helpers/deployed_revision_helper.rb and the page that renders it.
# Uses real REVISION files rather than stubbing File, so a malformed file
# is tested the way Capistrano would leave it.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)
require 'tmpdir'

RSpec.describe DeployedRevisionHelper, type: :helper do
  let(:sha) { 'a' * 40 }

  def with_revision_file(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'REVISION')
      File.write(path, content) unless content.nil?
      yield path
    end
  end

  describe '#deployed_revision' do
    it 'returns the hash, ignoring the trailing newline' do
      with_revision_file("#{sha}\n") do |path|
        expect(helper.deployed_revision(path)).to eq(sha)
      end
    end

    it 'returns nil when the file is missing' do
      with_revision_file(nil) do |path|
        expect(helper.deployed_revision(path)).to be_nil
      end
    end

    it 'returns nil when the file does not hold a full hash' do
      ['', 'abc1234', "#{'z' * 40}\n", "#{sha}\nextra"].each do |content|
        with_revision_file(content) do |path|
          expect(helper.deployed_revision(path)).to be_nil
        end
      end
    end
  end

  describe '#deployed_revision_link' do
    it 'links the short hash to the commit, with the full hash as the title' do
      html = helper.deployed_revision_link(sha, 'openaustralia/righttoknow')

      expect(html).to include(">#{'a' * 7}</a>")
      expect(html).to include(
        'href="https://github.com/openaustralia/righttoknow/commit/' \
        "#{sha}\""
      )
      expect(html).to include("title=\"#{sha}\"")
    end
  end
end

RSpec.describe 'GET /help/alaveteli', type: :request do
  let(:alaveteli_path) { Rails.root.join('REVISION') }
  let(:theme_path) { File.join(DeployedRevisionHelper::THEME_ROOT, 'REVISION') }
  let(:alaveteli_sha) { '1' * 40 }
  let(:theme_sha) { '2' * 40 }

  # Put real files in place and restore whatever was there, so the spec is
  # safe to run where a deploy has left genuine REVISION files.
  around do |example|
    originals = [alaveteli_path, theme_path].to_h do |path|
      [path.to_s, File.exist?(path) ? File.read(path) : nil]
    end
    example.run
  ensure
    originals.each do |path, content|
      content ? File.write(path, content) : FileUtils.rm_f(path)
    end
  end

  before do
    FileUtils.rm_f([alaveteli_path.to_s, theme_path])
  end

  it 'shows both commits as links to GitHub' do
    File.write(alaveteli_path, "#{alaveteli_sha}\n")
    File.write(theme_path, "#{theme_sha}\n")

    get '/help/alaveteli'

    expect(response.body).to include('Alaveteli commit:')
    expect(response.body).to include(
      "https://github.com/openaustralia/alaveteli/commit/#{alaveteli_sha}"
    )
    expect(response.body).to include('Right to Know theme commit:')
    expect(response.body).to include(
      "https://github.com/openaustralia/righttoknow/commit/#{theme_sha}"
    )
  end

  it 'still shows the theme commit when only the theme file exists' do
    File.write(theme_path, "#{theme_sha}\n")

    get '/help/alaveteli'

    expect(response.body).to include('Right to Know theme commit:')
    expect(response.body).not_to include('Alaveteli commit:')
  end

  it 'hides the version section when neither file exists' do
    get '/help/alaveteli'

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('commit:')
    expect(response.body).not_to include('<h2>Version</h2>')
  end

  it 'sets the page title' do
    get '/help/alaveteli'

    expect(response.body).to match(/<title>\s*Powered by Alaveteli/)
  end
end
