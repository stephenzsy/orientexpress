require_relative 'gen-rb/article_manager_constants'
require_relative 'gen-rb/article_manager'

require_relative '../version'

require_relative 'cache_manager'
require_relative 'article_vendor'
require_relative 'vendors/wsj'

module ColdBlossom
  module Darius
    module ArticleManager

      class ArticleManagerHandler

        def initialize config
          @cache_manager = S3CacheManager.new config
        end

        def version
          [
              ColdBlossom::Darius::MAJOR_VERSION,
              ColdBlossom::Darius::MINOR_VERSION,
              ColdBlossom::Darius::PATCH_VERSION
          ]
        end

        def health
          "OK"
        end

        def getOriginalDocument(request)
          vendor = ARTICLE_VENDORS[request.vendor]
          request.outputType ||= OutputType::S3_ARN
          request.schedulingOption ||= SchedulingOption::DEFAULT
          request.cacheOption ||= CacheOption::DEFAULT

          url = nil
          type = nil
          expire_before = nil
          expire_after = nil
          cache_partition = nil
          case request.documentType
            when DocumentType::DAILY_ARCHIVE_INDEX
              datetime = request.datetime.nil? ? Time.now : Time.parse(request.datetime)
              index_info = vendor.get_archive_index_info datetime, request.documentUrl
              type = 'daily_index'
              url = index_info[:url]
              expire_before = index_info[:expire_before]
              cache_partition = index_info[:cache_partition]
          end

          case request.outputType
            when OutputType::S3_ARN
              @cache_manager.get_document "#{vendor.name}:#{type}:raw", url, {:expire_before => expire_before, :expire_after => expire_after, :metadata_only => true, :cache_partition => cache_partition}
          end

          p vendor
          p request
          p datetime
        end

      end
    end
  end
end
