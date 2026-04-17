# frozen_string_literal: true

source 'https://rubygems.org'

group :development do
  gem 'guard'
  gem 'guard-livereload'
  gem 'json'
  gem 'rack-livereload'
  gem 'rb-fsevent'
  gem 'rb-inotify'
  gem 'rubocop', require: false
  gem 'ruby-lsp', require: false
end

group :deployment do
  gem 'capistrano', '~> 3.19'
  gem 'capistrano-bundler', '~> 2.1'
  gem 'capistrano-rails', '~> 1.6'
  gem 'capistrano-rbenv', '~> 2.2'
  gem 'capistrano-git-with-submodules', '~> 2.0'
  gem 'net-ssh', '~> 7.2'
  gem 'net-ssh-gateway', '>= 1.1.0', '< 3.0.0'
end
