# frozen_string_literal: true

require 'yaml'

configuration = YAML.load_file('config/deploy.yml')['production']

# Registers the EC2 instance(s) matching this stage's tags as deploy targets,
# with roles taken from each instance's Roles tag (app,web,db).
aws_ec2_register(user: configuration['user'])

set :repo_url,    configuration['repository']
set :branch,      configuration['branch']
set :deploy_to,   configuration['deploy_to']
set :rails_env,   configuration['rails_env']
set :daemon_name, configuration.fetch('daemon_name', 'alaveteli')
