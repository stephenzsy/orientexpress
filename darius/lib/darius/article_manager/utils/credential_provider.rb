require 'aws-sdk'

module ColdBlossom
  module Darius
    module ArticleManager
      module Utils
        class ConfigCredentialProvider
          include AWS::Core::CredentialProviders::Provider

          def initialize(config)
            @access_key_id = config[:access_key_id]
            @secret_access_key = config[:secret_access_key]
          end

          def access_key_id
            @access_key_id
          end

          def secret_access_key
            @secret_access_key
          end

          def credentials
            {
                :access_key_id => @access_key_id,
                :secret_access_key => @secret_access_key
            }
          end

        end

        class CredentialProvider
          def on_ec2_instance?
            output = `/opt/aws/bin/ec2-metadata 2>&1`
            return true if $?.exitstatus == 0
            false
          end

          def initialize(config)
            if on_ec2_instance?
              @inner_provider = AWS::Core::CredentialProviders::EC2Provider.new
            else
              @inner_provider = ConfigCredentialProvider.new config
            end
          end

          def method_missing(name, *args)
            @inner_provider.send(name, *args)
          end

        end
      end
    end
  end
end