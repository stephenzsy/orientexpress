require 'tempfile'

require_relative 'gen-rb/article_manager_types'

require_relative 'utils/async_worker'
require_relative 'archive_file'
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
          handle_build job
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

        def handle_build (job)
          bundle_date = Time.parse(job[:date])
          bundle = {
              :index_files => [],
              :article_files => []
          }
          temp_files = []
          begin
            result = @article_manager_client.getDocument(GetDocumentRequest.new do |r|
              r.vendor = job[:vendor]
              r.datetime = job[:date]
              r.documentType = DocumentType::DAILY_ARCHIVE_INDEX
              r.flavor = DocumentFlavor::PROCESSED_JSON
              r.outputType = OutputType::TEXT
            end)
            index = JSON.parse result.document, :symbolize_names => true

            # download index file
            result = @article_manager_client.getDocument(GetDocumentRequest.new do |r|
              r.vendor = job[:vendor]
              r.documentType = DocumentType::DAILY_ARCHIVE_INDEX
              r.flavor = job[:flavor]
              r.datetime = job[:date]
              r.outputType = OutputType::S3_ARN
            end)

            index_file = {:handle => Tempfile.new("archive_index_#{bundle_date.strftime '%Y%m%d'}-")}
            temp_files << index_file[:handle]
            begin
              @cache_manager.download_cached_file :arn, result.document, index_file[:handle] do |key, metadata|
                index_file[:metadata] = metadata.to_h
                index_file[:key] = key
              end
            ensure
              index_file[:handle].close
            end
            bundle[:index_files] << index_file

            article_seq = 0
            index[:articles].each do |article|
              article_seq += 1
              break if article_seq > 2 # TODO remove in production
              request = GetDocumentRequest.new do |r|
                r.vendor = job[:vendor]
                r.datetime = job[:date]
                r.documentType = DocumentType::ARTICLE
                r.flavor = job[:flavor]
                r.documentUrl = article[:url]
                r.outputType = OutputType::S3_ARN
              end
              r = @article_manager_client.getDocument request

              article_file = {:handle => Tempfile.new("archive_article_#{bundle_date.strftime '%Y%m%d'}-#{article_seq}-")}
              temp_files << article_file[:handle]
              begin
                @cache_manager.download_cached_file :arn, r.document, article_file[:handle] do |key, metadata|
                  article_file[:metadata] = metadata.to_h
                  article_file[:key] = key
                end
              ensure
                article_file[:handle].close
              end
              bundle[:article_files] << article_file
              p article_file
            end

            bundle_file = Tempfile.new 'archive_bundle'
            begin
              Archive::ArchiveFile.write_bundle bundle, bundle_file
            ensure
              bundle_file.close
            end

          rescue Exception => e
            p e
            p e.backtrace
            raise e
          ensure
            temp_files.each do |file|
              file.unlink
            end
          end
        end

      end
    end
  end
end