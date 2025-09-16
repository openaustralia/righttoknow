# Add a callback - to be executed before each request in development,
# and at startup in production - to patch existing app classes.
# See http://stackoverflow.com/questions/7072758/plugin-not-reloading-in-development-mode
#
Rails.configuration.to_prepare do
  # Override mailer templates with theme ones. Note doing this in a before_filter,
  # as we do with the controller paths, doesn't seem to have any effect when
  # running in production
  ActionMailer::Base.prepend_view_path File.join(File.dirname(__FILE__), 'views')
end
