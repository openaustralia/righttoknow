# frozen_string_literal: true

# Add a callback - to be executed before each request in development,
# and at startup in production - to patch existing app classes.
# Doing so in init/environment.rb wouldn't work in development, since
# classes are reloaded, but initialization is not run each time.
# See http://stackoverflow.com/questions/7072758/plugin-not-reloading-in-development-mode
#
Rails.configuration.to_prepare do
  HelpController.class_eval do
    before_action :set_history

    def house_rules; end

    private

    def set_history
      # Only set history if a template exists for this action
      template = lookup_context.find_template("#{controller_path}/#{action_name}")
      @history ||= HelpPageHistory.new(template)
    rescue ActionView::MissingTemplate
      # No template for this action, skip setting history
    end
  end
end
