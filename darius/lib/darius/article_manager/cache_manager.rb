require 'aws-sdk'
require 'digest/sha2'
require 'logger'
require 'timeout'
require 'pathname'

require_relative 'utils/configuration_util'

# Override to use Signature Version 4
module AWS
  class S3
    class Request
      include AWS::Core::Signature::Version4

      def add_authorization! (credentials)
        super credentials
      end

      #noinspection RubyArgCount
      def string_to_sign(datetime)
        super datetime
      end

      def service
        's3'
      end
    end
  end
end

module ColdBlossom
  module Darius
    module ArticleManager
      class CacheManager

        def get_document(topic, url, opt)
          raise 'Not Implemented'
        end

        def send_document(topic, url, opt)
          raise 'Not Implemented'
        end

      end

      class S3CacheManager < CacheManager

        def initialize(config)
          @log = Logger.new(STDOUT)
          @log.level = Logger::DEBUG

          @region = config[:region]
          @bucket_name = config[:s3_cache][:bucket]
          @s3_key_prefix = config[:s3_cache][:prefix]
          @s3 = AWS::S3.new ArticleManager::Utils::ConfigurationUtil.configure_aws config
          @s3_client = @s3.client
        end

        def head_archive(topic, date, opt)
          s3_key = "#{@s3_key_prefix}#{topic}/#{date.strftime '%Y/%m/%d'}"
          req = {:bucket_name => @bucket_name, :key => s3_key}
          begin
            res = @s3_client.head_object req
            metadata = response[:meta].symbolize_keys

            document_timestamp = Time.parse(metadata[:timestamp]) if metadata[:timestamp]

            if document_timestamp.nil? or
                (opt[:valid_after] and document_timestamp < opt[:valid_after])
              return :not_valid
            end

            if metadata[:error] == 'unavailable'
              return :unavailable
            end

            yield get_arn(s3_key), metadata
            :success
          rescue AWS::S3::Errors::NoSuchKey => e
            :not_exist
          end
        end


        def get_document(topic, url, opt)
          s3_key = get_s3_key topic, url, opt
          @log.debug s3_key
          begin
            response = nil
            req = {
                :bucket_name => @bucket_name,
                :key => s3_key
            }
            if opt[:metadata_only]
              response = @s3_client.head_object req
            else
              response = @s3_client.get_object req
              content = response[:data]
            end
            metadata = response[:meta].symbolize_keys

            # to be compatible with older documents
            document_timestamp = Time.parse(metadata[:timestamp]) if metadata[:timestamp]
            document_version = metadata[:document_version]

            if document_timestamp.nil? or
                (opt[:valid_after] and document_timestamp < opt[:valid_after]) or
                (opt[:allowed_document_versions] and opt[:allowed_document_versions].include? document_version)
              return :not_valid
            end

            if metadata[:error] == 'unavailable'
              return :unavailable
            end

            yield content, metadata, get_arn(s3_key)
            :success
          rescue AWS::S3::Errors::NoSuchKey => e
            :not_exist
          end
        end

        def put_document(topic, url, content, opt)
          s3_key = get_s3_key topic, url, opt
          case opt[:content_type]
            when :html
              content_type = 'text/html'
            when :json
              content_type = 'application/json'
          end
          metadata = opt[:metadata]
          metadata ||= {}
          metadata[:source] = url
          document_timestamp = opt[:timestamp]
          document_timestamp ||= Time.now
          metadata[:timestamp] = document_timestamp.utc.iso8601

          opt[:storage_class] ||= 'STANDARD'

          retry_count = 0
          begin
            @log.debug "send: #{s3_key}"
            Timeout::timeout(5) do
              @s3_client.put_object :bucket_name => @bucket_name,
                                    :key => s3_key,
                                    :data => content.dup,
                                    :storage_class => opt[:storage_class],
                                    :content_length => content.bytesize,
                                    :content_encoding => 'UTF-8',
                                    :content_type => content_type,
                                    :metadata => metadata
            end
            @log.debug "sent: #{s3_key}"
          rescue Exception => e
            retry_count += 1
            retry unless retry_count > 3
            raise e
          end
          get_arn s3_key
        end

        def download_cached_file(type, resource, file)
          case type
            when :arn
              req = arn_to_get_request resource
          end
          s3_obj = @s3.buckets[req[:bucket_name]].objects[req[:key]]
          s3_obj.read do |chunk|
            file.write(chunk)
          end
          yield req[:key], s3_obj.metadata
        end

        def upload_bundle(topic, content_date, bundled_file, opt = {})
          s3_key = "#{@s3_key_prefix}#{topic}/#{content_date.strftime '%Y/%m/%d'}"
          opt[:storage_class] ||= 'STANDARD'
          content_type = 'application/octet-stream'
          metadata = {}
          metadata[:bundler_version] = opt[:bundler_version] unless opt[:bundler_version].nil?
          metadata[:timestamp] = Time.now.utc.iso8601
          metadata[:content_date] = content_date.iso8601
          retry_count = 0
          begin
            Timeout::timeout(60) do
              @s3_client.put_object :bucket_name => @bucket_name,
                                    :key => s3_key,
                                    :data => Pathname.new(bundled_file),
                                    :storage_class => opt[:storage_class],
                                    :content_type => content_type,
                                    :metadata => metadata
            end
          rescue Exception => e
            retry_count += 1
            retry unless retry_count > 3
            raise e
          end
        end

        private
        def get_arn(s3_key)
          "arn:aws:s3:::#{@bucket_name}/#{s3_key}"
        end

        def get_s3_key(topic, url, opt)
          "#{@s3_key_prefix}#{topic}/#{opt[:cache_partition].nil? ? '' : opt[:cache_partition]}#{Digest::SHA2.hexdigest(url)}"
        end

        def arn_to_get_request(arn)
          if /arn:[\w-]+:s3:::(?<bucket_name>[^\/]+)\/(?<key>.*)/.match arn
            result = {:bucket_name => $~[:bucket_name], :key => $~[:key]}
          else
            raise "Not Valid ARN: #{arn}"
          end
          result
        end

      end
    end
  end
end
