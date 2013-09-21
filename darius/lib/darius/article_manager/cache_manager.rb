require 'aws-sdk'

module ColdBlossom
  module Darius
    module ArticleManager
      class CacheManager

        def get_document topic, type, flavor, url, opt
          raise 'Not Implemented'
        end

      end

      class S3CacheManager < CacheManager

      end
    end
  end
end
