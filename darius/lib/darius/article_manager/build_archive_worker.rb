require_relative 'gen-rb/article_manager_types'

require_relative 'utils/async_worker'
require_relative 'article_manager_base_client'

module ColdBlossom
  module Darius
    module ArticleManager
      class BuildArchiveWorker
        extend ArticleManager::Utils::WorkerClient
        include ArticleManager::Utils::WorkerServer

        def create(params)
          params[:archive_source] ||= ArchiveSource::NONE
          job = {
              :vendor => params[:vendor],
              :flavor => params[:flavor],
              :date => params[:date],
              :archive_source => params[:archive_source]
          }

          handle_validate_request job
          handle_check_archive job
          handle_retrieve_index job
        end

        private
        def handle_validate_request(job)
          case job[:archive_source]
            when ArchiveSource::NONE # only check existing
              job[:check_archive] = true
            when ArchiveSource::CACHE
              job[:check_archive] = false
            when ArchiveSource::SOURCE
              job[:check_archive] = false
            when ArchiveSource::EXTERNAL
              job[:check_archive] = false
            else
              raise "Unrecognized Archive Source Option: #{params[:archive_source]}"
          end
        end

        def handle_check_archive(job)
          return unless job[:check_archive]
        end

        def handle_retrieve_index(job)
          p job
          begin
            result = @article_manager_client.getDocument(GetDocumentRequest.new do |r|
              r.vendor = job[:vendor]
              r.datetime = job[:date]
              r.documentType = DocumentType::DAILY_ARCHIVE_INDEX
              r.flavor = DocumentFlavor::PROCESSED_JSON
              r.outputType = OutputType::TEXT
            end)
            index = JSON.parse result.document, :symbolize_names => true
            #puts JSON.pretty_generate index

            # download index file
            result = @article_manager_client.getDocument(GetDocumentRequest.new do |r|
              r.vendor = job[:vendor]
              r.documentType = DocumentType::DAILY_ARCHIVE_INDEX
              r.flavor = job[:flavor]
              r.datetime = job[:date]
              r.outputType = OutputType::S3_ARN
            end)
            @cache_manager.download_cached_file :arn, result.document
          rescue Exception => e
            p e
            p e.backtrace
            raise e
          end
        end
      end
    end
  end
end