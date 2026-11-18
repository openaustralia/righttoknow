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
      File.binwrite(path, content) unless content.nil?
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

    it 'returns nil when the file is not valid UTF-8' do
      with_revision_file("\xFF\xFE#{sha}".b) do |path|
        expect(helper.deployed_revision(path)).to be_nil
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
  let(:alaveteli_dir) { Dir.mktmpdir }
  let(:theme_dir) { Dir.mktmpdir }
  let(:alaveteli_path) { File.join(alaveteli_dir, 'REVISION') }
  let(:theme_path) { File.join(theme_dir, 'REVISION') }
  let(:alaveteli_sha) { '1' * 40 }
  let(:theme_sha) { '2' * 40 }

  # Point the helper at empty temp directories, so the spec never touches the
  # real REVISION files a deploy may have left.
  before do
    DeployedRevisionHelper.alaveteli_root = alaveteli_dir
    DeployedRevisionHelper.theme_root = theme_dir
  end

  after do
    DeployedRevisionHelper.alaveteli_root = nil
    DeployedRevisionHelper.theme_root = nil
    FileUtils.rm_rf([alaveteli_dir, theme_dir])
  end

  it 'shows both commits as links to GitHub' do
    File.write(alaveteli_path, "#{alaveteli_sha}\n")
    File.write(theme_path, "#{theme_sha}\n")

    get '/help/alaveteli'

    expect(response.body).to match(
      %r{This site is running\s+Alaveteli version\s+<a[^>]*>1{7}</a>\s+with\s+Right to Know theme version\s+<a[^>]*>2{7}</a>\s*\.}
    )
    expect(response.body).to include(
      "https://github.com/openaustralia/alaveteli/commit/#{alaveteli_sha}"
    )
    expect(response.body).to include(
      "https://github.com/openaustralia/righttoknow/commit/#{theme_sha}"
    )
  end

  it 'still shows the theme commit when only the theme file exists' do
    File.write(theme_path, "#{theme_sha}\n")

    get '/help/alaveteli'

    expect(response.body).to match(
      %r{This site is running\s+Right to Know theme version\s+<a[^>]*>2{7}</a>\s*\.}
    )
    expect(response.body).not_to include('Alaveteli version')
  end

  it 'hides the version section when neither file exists' do
    get '/help/alaveteli'

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('This site is running')
  end

  it 'sets the page title' do
    get '/help/alaveteli'

    expect(response.body).to match(/<title>\s*Powered by Alaveteli/)
  end
end
