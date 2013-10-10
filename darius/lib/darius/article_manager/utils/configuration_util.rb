require 'yaml'

require_relative 'credential_provider'

module ColdBlossom
  module Darius
    module ArticleManager
      module Utils
        class ConfigurationUtil
          def self.load_config_from_file(filename)
            YAML.load_file(filename)
          end

          def self.configure_aws(config)
            {
                :credential_provider => Utils::CredentialProvider.new(config),
                :region => config[:region],
                :logger => nil,
                :use_ssl => true
            }
          end
        end
      end
    end
  end
end
