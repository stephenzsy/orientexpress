require 'aws-sdk'
require 'digest/sha2'
require 'logger'
require 'timeout'

require_relative 'utils/credential_provider'

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
          @s3 = AWS::S3.new :credential_provider => Utils::CredentialProvider.new(config),
                            :region => config[:region],
                            :logger => nil,
                            :use_ssl => true
          @s3_client = @s3.client
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

            if document_timestamp.nil? or (opt[:valid_after] and document_timestamp < opt[:valid_after])
              return :not_valid
            end

            if metadata[:error] == 'unavailable'
              return :unavailable
            end

            yield content, metadata
            :success
          rescue AWS::S3::Errors::NoSuchKey => e
            :not_exist
          rescue Exception => e
            raise e
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
                                    :data => content,
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
          "arn:aws:s3:::#{@bucket_name}/#{s3_key}"
        end

        private
        def get_s3_key(topic, url, opt)
          "#{@s3_key_prefix}#{topic}/#{opt[:cache_partition].nil? ? '' : opt[:cache_partition]}#{Digest::SHA2.hexdigest(url)}"
        end

      end
    end
  end
end
