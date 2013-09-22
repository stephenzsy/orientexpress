require 'yaml'

module ColdBlossom
  module Darius
    module ArticleManager
      module Utils
        class ConfigurationUtil
          def self.load_config_from_file(filename)
            YAML.load_file(filename)
          end
        end
      end
    end
  end
end
