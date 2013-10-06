module ColdBlossom
  module Darius
    module ArticleManager

      class ArticleVendor
        def initialize(name)
          @name = name
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
