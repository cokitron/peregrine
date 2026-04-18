require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module FlightControl
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks])
    Rails.autoloaders.main.collapse("#{root}/lib/kiro_flow/nodes")

    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
    end
  end
end
