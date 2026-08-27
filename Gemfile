# frozen_string_literal: true

source 'https://rubygems.org'

group :development do
  gem 'guard'
  gem 'guard-livereload'
  gem 'json', '~> 2.6.2'
  gem 'rack-livereload'
  gem 'rb-fsevent'
  gem 'rb-inotify'
  gem 'rubocop', require: false
  gem 'ruby-lsp', require: false
end

group :deployment do
  gem 'bcrypt_pbkdf', '~> 1.1'
  gem 'capistrano', '~> 3.19'
  gem 'capistrano-aws', '~> 1.4'
  gem 'capistrano-bundler', '~> 2.1'
  gem 'capistrano-git-with-submodules', '~> 2.0'
  gem 'capistrano-maintenance', '~> 1.2'
  gem 'capistrano-rails', '~> 1.6'
  gem 'capistrano-rbenv', '~> 2.2'
  gem 'capistrano-tagging3', '~> 2.0'
  gem 'ed25519', '~> 1.3'
  gem 'net-ssh', '~> 7.2.0'
  gem 'net-ssh-gateway', '>= 1.1.0', '< 3.0.0'
  # aws-sdk-ec2 (via capistrano-aws) needs an XML library at runtime and this
  # bundle has no Rails to provide one; rexml is the lightest choice.
  gem 'rexml'
end
