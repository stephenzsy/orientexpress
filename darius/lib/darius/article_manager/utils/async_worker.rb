require_relative 'configuration_util'

module ColdBlossom
  module Darius
    module ArticleManager
      module Utils

        class AsyncWorkManager

          def initialize(config)
            @sqs = AWS::SQS.new ConfigurationUtil.configure_aws config
          end

          def submit(args, opt={})
          end

          def poll
            yield []
          end
        end

        module Worker

          def set_config config
            @manager = AsyncWorkManager.new config
            p @manager
          end

          def perform_async(args, opt = {})
            p args
            @manager.submit(args, opt)
            p opt
          end

        end

      end
    end
  end
end
