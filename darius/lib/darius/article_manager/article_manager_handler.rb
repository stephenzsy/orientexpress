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

          request.schedulingOption ||= SchedulingOption::DEFAULT

          job = {:request => request}

          handle_document_info job
          handle_get_cache job
          handle_get_external job
          handle_put_cache job
          handle_result job

          return job[:result]

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
                :cache_partition => cache_partition} do |content, metadata, arn|
              p content
              p metadata
              s3_arn = arn
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

        private

        def handle_document_info(job)
          request = job[:request]
          job[:vendor] = vendor = @vendors[request.vendor]
          job[:document_flavor] = request.flavor
          job[:document_flavor] ||= DocumentFlavor::RAW
          case job[:document_flavor]
            when DocumentFlavor::RAW
              job[:flavor] = 'raw'
              job[:content_type] = :html
            when DocumentFlavor::PROCESSED_JSON
              job[:flavor] = 'json'
              job[:content_type] = :json
            else
              raise ServiceException :statusCode => StatusCode::ERROR, :message => "Invalid Document Flavor: #{job[:document_flavor]}"
          end
          job[:document_type] = request.documentType
          case job[:document_type]
            when DocumentType::DAILY_ARCHIVE_INDEX
              job[:type] = 'daily_index'
              datetime = request.datetime.nil? ? Time.now : Time.parse(request.datetime)
              index_info = vendor.get_archive_index_info datetime, request.documentUrl
              job[:datetime] = index_info[:datetime]
              job[:url] = index_info[:url]
              job[:cache_partition] = index_info[:cache_partition]
              job[:cache_valid_after] = index_info[:valid_after]
            else
              raise ServiceException :statusCode => StatusCode::FAULT, :message => "Unsupported Document Type: #{job[:document_type]}"
          end
          job[:topic] = "#{vendor.name}:#{job[:type]}:#{job[:flavor]}"

          job[:output_type] = request.outputType
          job[:output_type] ||= OutputType::S3_ARN
        end

        def handle_get_cache(job)
          job[:cache_option] = job[:request].cacheOption
          job[:cache_option] ||= CacheOption::DEFAULT
          case job[:cache_option]
            when CacheOption::DEFAULT, CacheOption::ONLY_CACHE
              opt = {:cache_partition => job[:cache_partition]}
              opt[:valid_after] = job[:cache_valid_after] unless job[:cache_valid_after].nil?
              opt[:metadata_only] = (job[:output_type] == OutputType::S3_ARN)
              job[:cache_status] = @cache_manager.get_document job[:topic], job[:url], opt do |content, metadata, resource_name|
                job[:content] = content unless content.nil?
                job[:cache_metadata] = metadata
                job[:cache_arn] = resource_name
              end
              case job[:cache_status]
                when :success # do nothing
                when :not_valid, :not_exist
                  job[:external_retrieve] = true if job[:cache_option] == CacheOption::DEFAULT
                else
                  raise ServiceException :statusCode => StatusCode::FAULT, :message => "Internal Failure: Unsupported cache status: #{job[:cache_status]}"
              end
            when CacheOption::REFRESH, CacheOption::NO_CACHE # do nothing
              job[:external_retrieve] = true
            else
              raise ServiceException.new :statusCode => StatusCode::ERROR, :message => "Invalid Cache Option: #{job[:cache_option]}"
          end
        end

        def handle_get_external(job)
          return unless job[:external_retrieve]
          job[:vendor].get_external_document job[:url] do |doc, metadata|
            job[:content] = doc
            job[:external_metadata] = metadata
          end
        end

        def handle_put_cache(job)
          return unless job[:external_retrieve]
          job[:cache_arn] = @cache_manager.put_document job[:topic], job[:url], job[:content], {
              :cache_partition => job[:cache_partition],
              :content_type => job[:content_type],
              :metadata => job[:external_metadata]
          }
        end

        def handle_result(job)
          job[:result] = GetDocumentResult.new do |r|
            r.statusCode = StatusCode::SUCCESS
            r.timestamp = job[:datetime]
            case job[:output_type]
              when OutputType::S3_ARN
                r.document = job[:cache_arn]
              when OutputType::TEXT
                r.document = job[:content]
            end
          end
        end
      end
    end
  end
end
