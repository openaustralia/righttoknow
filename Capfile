# frozen_string_literal: true

require 'capistrano/setup'
require 'capistrano/deploy'

require 'capistrano/scm/git_with_submodules'
install_plugin Capistrano::SCM::GitWithSubmodules

require 'capistrano/bundler'
require 'capistrano/rails/assets'
require 'capistrano/rails/migrations'
require 'capistrano/rbenv'

Dir.glob('lib/capistrano/tasks/*.rake').each { |r| import r }
