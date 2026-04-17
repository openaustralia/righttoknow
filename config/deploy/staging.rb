# frozen_string_literal: true

require 'yaml'

configuration = YAML.load_file('config/deploy.yml')['staging']

server configuration['server'],
       user: configuration['user'],
       roles: %w[app web db]

set :branch,      configuration['branch']
set :deploy_to,   configuration['deploy_to']
set :rails_env,   configuration['rails_env']
set :daemon_name, configuration.fetch('daemon_name', 'alaveteli')
