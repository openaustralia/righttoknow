# frozen_string_literal: true

require 'bundler/capistrano'

set :stage, 'staging' unless exists? :stage

configuration = YAML.load_file('config/deploy.yml')[stage]

set :application, 'alaveteli'
set :scm, :git
set :deploy_via, :remote_cache
set :repository, configuration['repository']
set :branch, configuration['branch']
set :git_enable_submodules, true
set :deploy_to, configuration['deploy_to']
set :user, configuration['user']
set :use_sudo, false
set :rails_env, configuration['rails_env']
set :daemon_name, configuration.fetch('daemon_name', 'alaveteli')

server configuration['server'], :app, :web, :db, primary: true

set(:rbenv_ruby_version) do
  command = "cat #{shared_path}/rbenv-version 2>/dev/null || true"
  result = capture(command).strip
  result.empty? ? nil : result
end

if rbenv_ruby_version
  set(:rbenv_path) { capture('echo $HOME/.rbenv').strip }
  set(:rbenv_shims_path) { File.join(rbenv_path, 'shims') }
  set :default_environment, {
    'PATH' => [rbenv_shims_path, '$PATH'].join(':')
  }
end

namespace :themes do
  task :install do
    run "cd #{latest_release} && bundle exec rake themes:install RAILS_ENV=#{rails_env}"
  end
end

# Not in the rake namespace because we're also specifying app-specific arguments here
namespace :xapian do
  desc 'Rebuilds the Xapian index as per the ./scripts/destroy-and-rebuild-xapian-index script'
  task :destroy_and_rebuild_index do
    run "cd #{current_path} && bundle exec rake xapian:destroy_and_rebuild_index models='PublicBody User InfoRequestEvent' RAILS_ENV=#{rails_env}"
  end
end

set(:shared_children) do
  general_config = YAML.safe_load(capture("cat #{shared_path}/general.yml"))
  Array(general_config['SHARED_DIRECTORIES']).map { |d| File.basename(d.chomp('/')) }
end

namespace :deploy do
  desc 'Check that shared files and directories exist before deploying'
  task :check_shared do
    general_config = YAML.safe_load(capture("cat #{shared_path}/general.yml"))
    shared_files = Array(general_config['SHARED_FILES']).map { |f| "#{shared_path}/#{File.basename(f)}" }
    missing = shared_files.select { |f| capture("test -f #{f} && echo exists || echo missing").strip == 'missing' }
    abort "Missing shared files:\n#{missing.join("\n")}" unless missing.empty?
  end
  before 'deploy:symlink_configuration', 'deploy:check_shared'

  %i[start stop restart].each do |t|
    desc "#{t.to_s.capitalize} Alaveteli service defined in /etc/init.d/"
    task t, roles: :app, except: { no_release: true } do
      run "/etc/init.d/#{daemon_name} #{t}"
    end
  end

  desc 'Link configuration after a code update'
  task :symlink_configuration do
    general_config = YAML.safe_load(capture("cat #{shared_path}/general.yml"))
    shared_files = Array(general_config['SHARED_FILES'])
    shared_dirs = Array(general_config['SHARED_DIRECTORIES']).map { |d| d.chomp('/') }

    commands = (shared_files + shared_dirs).flat_map do |f|
      [
        "mkdir -p $(dirname #{release_path}/#{f})",
        "ln -snf #{shared_path}/#{File.basename(f)} #{release_path}/#{f}"
      ]
    end

    commands << "ln -snf #{shared_path}/rbenv-version #{release_path}/.rbenv-version" if rbenv_ruby_version

    run commands.join(' && ')
  end

  namespace :assets do
    desc 'Symlink non-digest asset paths to the most recent digest versions'
    task :link_non_digest do
      run "cd #{latest_release} && bundle exec rake assets:link_non_digest RAILS_ENV=#{rails_env}"
    end
  end

  after 'deploy:setup' do
    general_config = YAML.safe_load(capture("cat #{shared_path}/general.yml"))
    shared_dirs = Array(general_config['SHARED_DIRECTORIES']).map { |d| d.chomp('/') }
    dirs_to_create = shared_dirs.map { |d| "#{shared_path}/#{File.basename(d)}" }
    run dirs_to_create.map { |d| "mkdir -p #{d}" }.join(' && ')
  end
end

after 'deploy:assets:symlink', 'deploy:symlink_configuration'

before 'deploy:assets:precompile', 'themes:install'
after 'deploy:assets:precompile', 'deploy:assets:link_non_digest'

# Put up a maintenance notice if doing a migration which could take a while
before 'deploy:migrate', 'deploy:web:disable'
after 'deploy:migrate', 'deploy:web:enable'
