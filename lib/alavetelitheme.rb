# frozen_string_literal: true

theme_name = File.split(File.expand_path('..', __dir__))[1]
theme_name.gsub!('-', '_')
THEME_NAME = theme_name

Rails.application.config.assets.precompile << ['alaveteli_pro/coupon_preview.js']

module ActionController
  class Base
    # The following prepends the path of the current theme's views to
    # the "filter_path" that Rails searches when deciding which
    # template to use for a view.  It does so by creating a method
    # uniquely named for this theme.
    path_function_name = "set_view_paths_for_#{THEME_NAME}"
    before_action path_function_name.to_sym
    send :define_method, path_function_name do
      prepend_view_path File.join(File.dirname(__FILE__), 'views')
    end
  end
end

# In order to have the theme lib/ folder ahead of the main app one,
# inspired in Ruby Guides explanation: http://guides.rubyonrails.org/plugins.html
%w[.].each do |dir|
  path = File.join(File.dirname(__FILE__), dir)
  $LOAD_PATH.insert(0, path)
end

# Monkey patch app code
['controller_patches.rb',
 'model_patches.rb',
 'helper_patches.rb',
 'patch_mailer_paths.rb'].each do |patch|
  require File.expand_path "../#{patch}", __FILE__
end

# Error monitoring and APM (no-op unless the sentry gems and DSN are present)
require File.expand_path('sentry_config.rb', __dir__)

# A new controller (not a patch to an existing one) - see its own file for why
require File.expand_path('whatismyip_controller.rb', __dir__)

# Note you should rename the file at "config/custom-routes.rb" to
# something unique (e.g. yourtheme-custom-routes.rb":
$alaveteli_route_extensions << 'custom-routes.rb'

# Append individual theme assets to the asset path
theme_asset_path = File.join(File.dirname(__FILE__),
                             '..',
                             'app',
                             'assets')
theme_asset_path = Pathname.new(theme_asset_path).cleanpath.to_s

LOOSE_THEME_ASSETS = lambda do |logical_path, filename|
  filename.start_with?(theme_asset_path) &&
    !['.js', '.css', ''].include?(File.extname(logical_path))
end
Rails.application.config.assets.precompile.unshift(LOOSE_THEME_ASSETS)

def prepend_theme_assets
  # Prepend the asset directories in this theme to the asset path:
  %w[stylesheets images javascripts fonts].each do |asset_type|
    theme_asset_path = File.join(File.dirname(__FILE__),
                                 '..',
                                 'app',
                                 'assets',
                                 asset_type)

    Rails.application.config.assets.paths.unshift theme_asset_path
  end
end

Rails.application.config.to_prepare do
  prepend_theme_assets
end

# Tell FastGettext about the theme's translations: look in the theme's
# locale-theme directory for a translation in the first place, and if
# it isn't found, look in the Alaveteli locale directory next:
repos = [
  FastGettext::TranslationRepository.build('app', path: File.join(File.dirname(__FILE__), '..', 'locale-theme'),
                                                  type: :po),
  FastGettext::TranslationRepository.build('app', path: 'locale', type: :po)
]
FastGettext.add_text_domain 'app', type: :chain, chain: repos
FastGettext.default_text_domain = 'app'
