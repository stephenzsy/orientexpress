require_relative 'gen-rb/article_manager_types'

module ColdBlossom
  module Darius
    module ArticleManager
      module GetBatchHandlers

        def get_archive_handle_request(job)
          request = job[:request]
          raise ServiceException.new :statusCode => StatusCode::ERROR, :message => "Unrecognized vendor: #{request.vendor}" unless @vendors.has_key? request.vendor
          job[:vendor] = @vendors[request.vendor]
          job[:flavor] = request.flavor
          job[:flavor] ||= DocumentFlavor::PROCESSED_JSON
          job[:date] = job[:vendor].get_batch_date request.date
          job[:archive_source] = request.archiveSource
          job[:archive_source] ||= ArchiveSource::CACHE
        end

        def get_archive_handle_check_existing(job)
          if job[:archive_source] == ArchiveSource::NONE or ArchiveSource::CACHE
            p job
          else
          end
        end

        def get_archive_handle_result(job)
          job[:result] = 'Not Ready'
        end

      end
    end
  end
end