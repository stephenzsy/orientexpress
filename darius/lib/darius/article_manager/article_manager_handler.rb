require 'thrift'
require 'logger'
require_relative 'gen-rb/article_manager_types'
require_relative 'gen-rb/article_manager_constants'
require_relative 'gen-rb/article_manager'

require_relative 'get_archive_handlers'

require_relative '../version'

require_relative 'cache_manager'

require_relative 'article_vendor'
require_relative 'vendors/wsj'


module ColdBlossom
  module Darius
    module ArticleManager
      class ArticleManagerHandler
        include GetBatchHandlers

        def initialize config
          @cache_manager = S3CacheManager.new config
          @vendors = {
              'wsj' => Vendors::WSJ.new(config)
          }
          @log = Logger.new(STDOUT)
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
          begin
            job = {:request => request}

            handle_document_info job
            handle_get_cache job
            handle_get_external job
            handle_put_cache job
            handle_result job

            job[:result]
          rescue ServiceException => e
            raise e
          rescue Exception => e
            puts e.message
            puts e.backtrace
            raise ServiceException.new :statusCode => StatusCode::FAULT, :message => e.message
          end
        end

        def getArchive(request)
          begin
            job = {:request => request}

            get_archive_handle_request job
            get_archive_handle_check_existing job

            job[:result]
          rescue ServiceException => e
            raise e
          rescue Exception => e
            puts e.message
            puts e.backtrace
            raise ServiceException.new :statusCode => StatusCode::FAULT, :message => e.message
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
              raise ServiceException.new :statusCode => StatusCode::ERROR, :message => "Invalid Document Flavor: #{job[:document_flavor]}"
          end
          job[:document_type] = request.documentType
          case job[:document_type]
            when DocumentType::ARTICLE
              job[:type] = 'article'
              raise ServiceException.new :statusCode => StatusCode::ERROR, :message => "datetime must be provided in the input for article retrieval" if request.datetime.nil?
              datetime = Time.parse request.datetime
              article_info = vendor.get_article_info datetime, request.documentUrl
              job[:datetime] = article_info[:datetime]
              job[:url] = article_info[:url]
              job[:cache_partition] = article_info[:cache_partition]
            when DocumentType::DAILY_ARCHIVE_INDEX
              job[:type] = 'daily_index'
              datetime = request.datetime.nil? ? Time.now : Time.parse(request.datetime)
              index_info = vendor.get_archive_index_info datetime, request.documentUrl
              job[:datetime] = index_info[:datetime]
              job[:url] = index_info[:url]
              job[:cache_partition] = index_info[:cache_partition]
              job[:cache_valid_after] = index_info[:valid_after]
            else
              raise ServiceException.new :statusCode => StatusCode::FAULT, :message => "Unsupported Document Type: #{job[:document_type]}"
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
                  @log.debug 'Cache SUCCESS'
                  job[:external_retrieve] = false
                when :not_valid, :not_exist
                  @log.debug 'Cache FAIL'
                  job[:external_retrieve] = true if job[:cache_option] == CacheOption::DEFAULT
                else
                  raise ServiceException.new :statusCode => StatusCode::FAULT, :message => "Internal Failure: Unsupported cache status: #{job[:cache_status]}"
              end
            when CacheOption::REFRESH, CacheOption::NO_CACHE # do nothing
              job[:external_retrieve] = true
            else
              raise ServiceException.new :statusCode => StatusCode::ERROR, :message => "Invalid Cache Option: #{job[:cache_option]}"
          end
        end

        def handle_get_external(job)
          return unless job[:external_retrieve]
          case job[:document_flavor]
            when DocumentFlavor::RAW
              job[:vendor].get_external_document job[:url] do |doc, metadata|
                job[:content] = doc
                @log.debug "External Content Encoding: #{job[:content].encoding}"
                job[:external_metadata] = metadata
              end
            when DocumentFlavor::PROCESSED_JSON
              original_request = job[:request]
              request = GetDocumentRequest.new do |r|
                r.vendor = original_request.vendor
                r.documentType = original_request.documentType
                r.flavor = DocumentFlavor::RAW
                r.documentUrl = original_request.documentUrl
                r.datetime = original_request.datetime
                r.outputType = OutputType::TEXT
                r.cacheOption = original_request.cacheOption
              end
              result = getDocument request
              case job[:document_type]
                when DocumentType::ARTICLE
                  job[:vendor].article_to_json job[:url], result.document do |json_obj, metadata|
                    job[:content] = JSON.generate json_obj
                    job[:external_metadata] = metadata
                  end
                when DocumentType::DAILY_ARCHIVE_INDEX
                  job[:vendor].daily_archive_index_to_json result.document do |json_obj, metadata|
                    job[:content] = JSON.generate json_obj
                    job[:external_metadata] = metadata
                  end
                else
                  raise ServiceException.new :statusCode => StatusCode::ERROR, :message => "Invalid Document Type: #{job[:document_type]}"
              end
            else
              raise ServiceException.new :statusCode => StatusCode::ERROR, :message => "Invalid Document Flavor: #{job[:document_flavor]}"
          end
        end

        def handle_put_cache(job)
          return unless job[:external_retrieve]
          storage_class = 'REDUCED_REDUNDANCY' if job[:document_flavor] == DocumentFlavor::PROCESSED_JSON
          job[:cache_arn] = @cache_manager.put_document job[:topic], job[:url], job[:content], {
              :cache_partition => job[:cache_partition],
              :content_type => job[:content_type],
              :metadata => job[:external_metadata],
              :storage_class => storage_class
          }
        end

        def handle_result(job)
          job[:result] = GetDocumentResult.new do |r|
            r.statusCode = StatusCode::SUCCESS
            r.timestamp = job[:datetime].iso8601
            case job[:output_type]
              when OutputType::S3_ARN
                r.document = job[:cache_arn]
              when OutputType::TEXT
                job[:content].force_encoding('UTF-8')
                raise 'Content not valid UTF-8 encoding' unless job[:content].valid_encoding?
                r.document = job[:content]
            end
          end
        end
      end
    end
  end
end
