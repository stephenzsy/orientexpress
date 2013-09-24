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
          @vendors = {
              'wsj' => Vendors::WSJ.new(config)
          }
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

        def getDocument(request)
          vendor = @vendors[request.vendor]
          request.outputType ||= OutputType::S3_ARN
          request.schedulingOption ||= SchedulingOption::DEFAULT
          request.cacheOption ||= CacheOption::DEFAULT
          request.flavor ||= DocumentFlavor::RAW

          case request.flavor
            when DocumentFlavor::RAW
              flavor = 'raw'
              content_type = :html
            when DocumentFlavor::PROCESSED_JSON
              flavor = 'json'
              content_type = :json
            else
              raise 'WTF'
          end

          url = nil
          type = nil
          valid_after = nil
          expire_after = nil
          cache_partition = nil
          case request.documentType
            when DocumentType::DAILY_ARCHIVE_INDEX
              datetime = request.datetime.nil? ? Time.now : Time.parse(request.datetime)
              index_info = vendor.get_archive_index_info datetime, request.documentUrl
              type = 'daily_index'
              datetime = index_info[:datetime]
              url = index_info[:url]
              valid_after = index_info[:valid_after]
              cache_partition = index_info[:cache_partition]
          end

          topic = "#{vendor.name}:#{type}:#{flavor}"

          metadata_only = true
          case request.outputType
            when OutputType::S3_ARN
              metadata_only = true
          end

          skip_get_cache = false
          skip_send_cache = false
          cache_only = false

          case request.cacheOption
            when CacheOption::DEFAULT
              skip_get_cache = false
          end

          cache_error = nil

          unless skip_get_cache
            cache_status_code = @cache_manager.get_document topic, url, {
                :valid_after => valid_after,
                :expire_after => expire_after,
                :metadata_only => true,
                :cache_partition => cache_partition} do |content, metadata|
              p content
              p metadata
            end

            case cache_status_code
              when :success
                # TODO: format return
              when :not_valid, :not_exist
                if cache_only
                  raise 'TODO'
                end
              else
                raise 'WTF'
            end
          end

          document = nil
          external_document_metadata = nil
          vendor.get_external_document url do |doc, metadata|
            document = doc
            external_document_metadata = metadata
          end

          unless skip_send_cache
            s3_arn = @cache_manager.put_document topic, url, document, {
                :cache_partition => cache_partition,
                :content_type => content_type,
                :metadata => external_document_metadata
            }
          end

          GetDocumentResult.new do |r|
            r.statusCode = StatusCode::SUCCESS
            r.timestamp = datetime
            case request.outputType
              when OutputType::S3_ARN
                r.document = s3_arn
            end
          end


        end

      end
    end
  end
end
