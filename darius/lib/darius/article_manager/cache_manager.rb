require 'aws-sdk'

module ColdBlossom
  module Darius
    module ArticleManager
      class CacheManager

        def get_document(topic, url, opt)
        raise 'Not Implemented'
        end

      end

      class S3CacheManager < CacheManager
        def initialize(config)
          @region = config[:region]
          @bucket_name = config[:s3_cache][:bucket]
          @s3_key_prefix = config[:s3_cache][:prefix]
        end

        def get_document(topic, url, opt)
          s3_key = get_s3_key topic, url, opt
          p s3_key
        end

        private
        def get_s3_key(topic, url, opt)
          "#{@s3_key_prefix}#{topic}/#{opt[:cache_partition].nil? ? '' : opt[:cache_partition]}#{Digest::SHA2.hexdigest(url)}"
        end


        protected
        def retrieve_from_cache(topic, key_part, url, cache_cutoff = nil, cache_cutoff_key = nil)
          s3_key = "#{@prefix}#{topic}/#{key_part}#{Digest::SHA2.hexdigest(url)}"
          p s3_key
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
