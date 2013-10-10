require_relative 'gen-rb/article_manager_types'
require_relative 'build_archive_worker'

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
          job[:archive_info] = job[:vendor].get_archive_info request.date
          job[:archive_source] = request.archiveSource
          job[:archive_source] ||= ArchiveSource::CACHE
        end

        def get_archive_handle_check_existing(job)
          if job[:archive_source] == ArchiveSource::NONE or job[:archive_source] == ArchiveSource::CACHE
            cache_result = @cache_manager.head_archive "#{job[:vendor].name}:archive", job[:archive_info][:date], job[:archive_info] do |s3_arn, metadata|
              p s3_arn
              p metadata
            end
            case cache_result
              when :success
                # TODO get the information
                raise 'Need Developer'
              else
                job[:build_archive] = true
            end
          else
          end
        end

        def get_archive_handle_build_archive(job)
          return unless job[:build_archive]
          BuildArchiveWorker.perform_async :create, {:vendor => job[:vendor].name, :date => job[:archive_info][:date], :archive_source => job[:archive_source]}
          p job
        end

        def get_archive_handle_result(job)
          job[:result] = 'Not Ready'
        end

      end
    end
  end
end