# frozen_string_literal: true

require 'stringio'
require 'yaml'

set :application, 'alaveteli'
set :use_sudo,    false

set :rbenv_type, :user

# net-ssh misinterprets the ^ modifier syntax in ~/.ssh/config Ciphers entries,
# leaving the client cipher list empty and causing algorithm negotiation to fail.
# Setting encryption explicitly bypasses that and still matches all server ciphers.
set :ssh_options, {
  encryption: %w[chacha20-poly1305@openssh.com aes256-gcm@openssh.com
                 aes128-gcm@openssh.com aes256-ctr aes192-ctr aes128-ctr]
}

# Merge theme gems into alaveteli's bundle so they are on Rails' load path.
# Deployment mode (bundle config deployment true) rejects a modified Gemfile,
# so we disable it and rely on the shared bundle path for persistence.
set :bundle_config, {}
set :bundle_without, %w[development test deployment].join(':')

# Write the maintenance page as current/public/down.html so it's picked up by
# the nginx / apache rules alaveteli ships with (see alaveteli's
# config/nginx.conf.example and httpd.conf-example).
set :maintenance_basename, 'down'
set :maintenance_dirname,  -> { current_path.join('public') }

# Tagging options
set :tagging3_format, ':stage_:release'

# Read the Ruby version from the server's shared rbenv-version file,
# matching the version installed by the infrastructure repo.
task :set_rbenv_ruby do
  on roles(:app) do
    rbenv_version_file = "#{fetch(:deploy_to)}/shared/rbenv-version"
    if test("[ -f #{rbenv_version_file} ]")
      set :rbenv_ruby, capture(:cat, rbenv_version_file).strip
    else
      warn "Warning: #{rbenv_version_file} not found; :rbenv_ruby not set"
    end
  end
end
before 'deploy:starting', :set_rbenv_ruby

namespace :themes do
  desc 'Install Alaveteli themes'
  task :install do
    on roles(:app) do
      within release_path do
        execute :bundle, "exec rake themes:install RAILS_ENV=#{fetch(:rails_env)}"
      end
    end
  end

  desc 'Upload Gemfile.theme and inject into alaveteli Gemfile before bundle install'
  task :pre_bundle_setup do
    on roles(:app) do
      theme_dir = release_path.join('lib', 'themes', 'righttoknow')
      execute :mkdir, '-p', theme_dir
      # Upload Gemfile.theme (theme runtime gems only) rather than the theme
      # repo's main Gemfile, which carries dev/deployment tooling we don't
      # want leaking into alaveteli's server bundle. The uploaded file is
      # renamed to "Gemfile" in the release so eval_gemfile finds it.
      upload! 'Gemfile.theme', "#{theme_dir}/Gemfile"
      execute :bash, '-c',
              "echo \"\\neval_gemfile '#{theme_dir}/Gemfile'\" >> #{release_path.join('Gemfile')}"
    end
  end
end

namespace :xapian do
  desc 'Rebuilds the Xapian index as per the ./scripts/destroy-and-rebuild-xapian-index script'
  task :destroy_and_rebuild_index do
    on roles(:app) do
      within current_path do
        execute :bundle,
                "exec rake xapian:destroy_and_rebuild_index models='PublicBody User InfoRequestEvent' RAILS_ENV=#{fetch(:rails_env)}"
      end
    end
  end
end

namespace :deploy do
  # The shared files on this server are laid out by basename
  # (shared/database.yml rather than shared/config/database.yml), which does
  # not match Cap 3's built-in :linked_files convention. We keep a custom
  # symlink task for that reason; see deploy:symlink_configuration below.
  desc 'Check that shared files and directories exist before deploying'
  task :check_shared do
    on roles(:app) do
      general_config = YAML.safe_load(capture(:cat, "#{shared_path}/general.yml"))
      shared_files = Array(general_config['SHARED_FILES']).map { |f| shared_path.join(File.basename(f)) }
      shared_dirs  = Array(general_config['SHARED_DIRECTORIES']).map do |d|
        shared_path.join(File.basename(d.chomp('/')))
      end

      missing_files = shared_files.reject { |f| test("[ -f #{f} ]") }
      raise "Missing shared files:\n#{missing_files.join("\n")}" unless missing_files.empty?

      # Shared directories hold runtime data (cache, logs, storage, xapian
      # indexes, the vendored bundle). Create any that are missing rather than
      # failing the deploy — they're safe to initialise empty.
      shared_dirs.each do |d|
        execute :mkdir, '-p', d unless test("[ -d #{d} ]")
      end
    end
  end

  desc 'Link configuration files and directories from shared path into release'
  task :symlink_configuration do
    on roles(:app) do
      general_config = YAML.safe_load(capture(:cat, "#{shared_path}/general.yml"))
      shared_files = Array(general_config['SHARED_FILES'])
      shared_dirs  = Array(general_config['SHARED_DIRECTORIES']).map { |d| d.chomp('/') }

      (shared_files + shared_dirs).each do |f|
        target = release_path.join(f)
        source = shared_path.join(File.basename(f))
        execute :mkdir, '-p', File.dirname(target)
        execute :ln, '-snf', source, target
      end

      rbenv_version_path = shared_path.join('rbenv-version')
      if test("[ -f #{rbenv_version_path} ]")
        execute :ln, '-snf', rbenv_version_path,
                release_path.join('.rbenv-version')
      end
    end
  end

  namespace :assets do
    desc 'Symlink non-digest asset paths to the most recent digest versions'
    task :link_non_digest do
      on roles(:app) do
        within release_path do
          execute :bundle, "exec rake assets:link_non_digest RAILS_ENV=#{fetch(:rails_env)}"
        end
      end
    end
  end

  # Cap 3 deploys via git archive which strips .git, breaking runtime git
  # commands used by alaveteli (git branch, git log -1, git remote show) and
  # the `git submodule status commonlib` check in lib/tasks/submodules.rake.
  # This task creates a real .git in the release using git's own commands,
  # backed by the bare repo's object store via alternates.
  #
  # Caveat: objects/info/alternates ties the release to the bare repo at
  # repo_path. If the bare repo is ever pruned/gc'd or rebuilt, objects
  # referenced by older releases become unreachable. Mitigate by not pruning
  # and by redeploying rather than rolling back across a bare-repo rebuild.
  desc 'Create a real .git in the release so runtime git commands work'
  task :setup_git do
    on roles(:app) do
      within release_path do
        commit = capture(:cat, release_path.join('REVISION')).strip
        branch = fetch(:branch)

        execute :rm, '-rf', '.git'
        execute :git, 'init', '--quiet'
        execute :git, 'remote', 'add', 'origin', fetch(:repo_url)
        # Ensure objects/info exists before writing alternates; some git
        # versions populate objects/ lazily.
        execute :mkdir, '-p', '.git/objects/info'
        # upload! takes an absolute path and writes the content via SFTP,
        # side-stepping the quoting pitfalls of a shell redirect.
        upload! StringIO.new("#{repo_path.join('objects')}\n"),
                release_path.join('.git', 'objects', 'info', 'alternates')
        execute :git, 'update-ref', "refs/heads/#{branch}", commit
        execute :git, 'symbolic-ref', 'HEAD', "refs/heads/#{branch}"
        # Reset the index to match HEAD so `git status` / `git diff` are
        # clean; without this git reports every working-tree file as added.
        execute :git, 'reset', '--mixed', '--quiet'

        # capistrano-git-with-submodules has already checked out submodule
        # content into the release and wiped their .git dirs; `git submodule
        # init` reads .gitmodules and registers the submodule URLs in our new
        # .git/config so `git submodule status` (used by rake submodules:check)
        # can report on them.
        execute :git, 'submodule', 'init' if test('[ -f .gitmodules ]')
      end
    end
  end

  %i[start stop restart].each do |t|
    desc "#{t.to_s.capitalize} Alaveteli service defined in /etc/init.d/"
    task t do
      on roles(:app) do
        execute "/etc/init.d/#{fetch(:daemon_name)} #{t}"
      end
    end
  end
end

before 'deploy:starting',             'deploy:check_shared'
after  'deploy:set_current_revision', 'deploy:setup_git'
after  'deploy:symlink:shared',       'deploy:symlink_configuration'

before 'bundler:install',          'themes:pre_bundle_setup'
before 'deploy:assets:precompile', 'themes:install'
after  'deploy:assets:precompile', 'deploy:assets:link_non_digest'

# Show a maintenance page during migrations. current/ still points at the
# previous release while deploy:migrate runs, so the file is served from the
# old release and removed before the new release is published.
before 'deploy:migrate', 'maintenance:enable'
after  'deploy:migrate', 'maintenance:disable'

after 'deploy:finishing', 'deploy:restart'
