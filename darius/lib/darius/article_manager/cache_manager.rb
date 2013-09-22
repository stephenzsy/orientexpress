require 'aws-sdk'
require 'digest/sha2'
require 'logger'

require_relative 'utils/credential_provider'

module ColdBlossom
  module Darius
    module ArticleManager
      class CacheManager

        class Exception < StandardError
          attr_accessor :status_code

          def initialize(status_code, message)
            super message
            self.status_code = status_code
          end
        end

        def get_document(topic, url, opt)
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
            p req
            if opt[:metadata_only]
              response = @s3_client.head_object req
            else
              response = @s3_client.get_object req
              content = response[:data]
            end
            metadata = response[:meta].symbolize_keys
            document_timestamp = nil
            if metadata[:timestamp]
              document_timestamp = Time.parse(metadata[:timestamp])
            elsif metadata[:retrieval_time]
              document_timestamp = Time.parse(metadata[:retrieval_time])
            end
            if opt[:expire_before] and document_timestamp < opt[:expire_before]
              raise CacheManager::Exception.new :expired, "Document timestamp: #{document_timestamp.utc.iso8601} is earlier than the required expiry: #{opt[:expire_before].utc.iso8601}"
            end
            yield content, metadata
          rescue AWS::S3::Errors::NoSuchKey => e
            return false
          rescue Exception => e
            raise e
          end
        end

        private
        def get_s3_key(topic, url, opt)
          "#{@s3_key_prefix}#{topic}/#{opt[:cache_partition].nil? ? '' : opt[:cache_partition]}#{Digest::SHA2.hexdigest(url)}"
        end


        protected
        def retrieve_from_cache(topic, key_part, url, cache_cutoff = nil, cache_cutoff_key = nil)
          s3_key = "#{@prefix}#{topic}/#{key_part}#{Digest::SHA2.hexdigest(url)}"
          begin
            response = @s3_client.get_object :bucket_name => @bucket, :key => s3_key
            content = response[:data]
            metadata = response[:meta].symbolize_keys
          rescue AWS::S3::Errors::NoSuchKey => e
            return false
          rescue Exception => e
            raise e
          end
          unless cache_cutoff.nil?
            return false if metadata[cache_cutoff_key].nil? or Time.parse(metadata[cache_cutoff_key]) < cache_cutoff
          end
          yield content, metadata
        end
      end
    end
  end
end
