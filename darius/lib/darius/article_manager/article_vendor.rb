module ColdBlossom
  module Darius
    module ArticleManager

      class ArticleVendor
        attr_accessor :allowed_document_versions, :allowed_article_processor_versions, :allowed_daily_archive_index_processor_versions

        def initialize(name)
          @name = name
          self.allowed_document_versions = nil
          self.allowed_article_processor_versions = nil
          self.allowed_daily_archive_index_processor_versions = nil
        end

        def name
          @name
        end

        def get_archive_index_info(datetime, url)
          raise 'Not Supported'
        end

        def daily_archive_index_to_json
          raise 'Not Supported'
        end

        def get_article_info(datetime, url)
          raise 'Not Supported'
        end

        def article_to_json(url, document)
          raise 'Not Supported'
        end
      end
    end
  end
end
