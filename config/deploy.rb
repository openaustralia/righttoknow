# frozen_string_literal: true

require 'yaml'

set :application, 'alaveteli'
set :repo_url,    'https://github.com/openaustralia/alaveteli.git'
set :use_sudo,    false

set :rbenv_type, :user

# Read the Ruby version from the server's shared rbenv-version file,
# matching the version installed by the infrastructure repo.
task :set_rbenv_ruby do
  on roles(:app) do
    rbenv_version_file = "#{fetch(:deploy_to)}/shared/rbenv-version"
    if test("[ -f #{rbenv_version_file} ]")
      set :rbenv_ruby, capture(:cat, rbenv_version_file).strip
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

  desc 'Install gems declared in the theme Gemfile into the shared bundle'
  task :bundle_install do
    on roles(:app) do
      theme_gemfile = release_path.join('lib', 'themes', 'righttoknow', 'Gemfile')
      next unless test("[ -f #{theme_gemfile} ]")
      within release_path do
        execute :bundle, 'install', '--gemfile', theme_gemfile,
                '--without', 'development deployment'
      end
    end
  end
end

namespace :xapian do
  desc 'Rebuilds the Xapian index as per the ./scripts/destroy-and-rebuild-xapian-index script'
  task :destroy_and_rebuild_index do
    on roles(:app) do
      within current_path do
        execute :bundle, "exec rake xapian:destroy_and_rebuild_index models='PublicBody User InfoRequestEvent' RAILS_ENV=#{fetch(:rails_env)}"
      end
    end
  end
end

namespace :deploy do
  desc 'Check that shared files exist before deploying'
  task :check_shared do
    on roles(:app) do
      general_config = YAML.safe_load(capture(:cat, "#{shared_path}/general.yml"))
      shared_files = Array(general_config['SHARED_FILES']).map { |f| shared_path.join(File.basename(f)) }
      missing = shared_files.reject { |f| test("[ -f #{f} ]") }
      raise "Missing shared files:\n#{missing.join("\n")}" unless missing.empty?
    end
  end

  desc 'Create shared directories (run once on new server setup)'
  task :setup do
    on roles(:app) do
      general_config = YAML.safe_load(capture(:cat, "#{shared_path}/general.yml"))
      shared_dirs = Array(general_config['SHARED_DIRECTORIES']).map { |d| d.chomp('/') }
      shared_dirs.each do |d|
        execute :mkdir, '-p', shared_path.join(File.basename(d))
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
        execute :ln, '-snf', rbenv_version_path, release_path.join('.rbenv-version')
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

  %i[start stop restart].each do |t|
    desc "#{t.to_s.capitalize} Alaveteli service defined in /etc/init.d/"
    task t do
      on roles(:app) do
        execute "/etc/init.d/#{fetch(:daemon_name)} #{t}"
      end
    end
  end
end

before 'deploy:starting',       'deploy:check_shared'
after  'deploy:symlink:shared', 'deploy:symlink_configuration'

before 'deploy:assets:precompile', 'themes:install'
after  'themes:install',           'themes:bundle_install'
after  'deploy:assets:precompile', 'deploy:assets:link_non_digest'

before 'deploy:migrate', 'deploy:web:disable'
after  'deploy:migrate', 'deploy:web:enable'
