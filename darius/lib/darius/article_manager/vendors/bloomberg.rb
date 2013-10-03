require 'active_support/all'

require_relative '../article_vendor'
require_relative '../utils/cookie_helper'

module ColdBlossom
  module Darius
    module ArticleManager
      module Vendors
        class Bloomberg < ArticleVendor

          VENDOR_NAME = 'Bloomberg'
          EXTERNAL_DOCUMENT_VERSION = '2013-10-01'

          Time.zone = 'America/New_York'

          def initialize(config)
            @log = Logger.new(STDOUT)
            @log.level = Logger::DEBUG

            super VENDOR_NAME
            set_cookie_store config, self
            set_authentication_cookies(get_stored_cookies())
          end

          def get_archive_index_url datetime
            "http://online.wsj.com/public/page/archive-#{datetime.strftime "%Y-%-m-%-d"}.html"
          end

          def get_archive_index_info datetime, url = nil
            datetime = datetime.in_time_zone.midnight
            index_url = get_archive_index_url datetime

            if url.nil?
              url = index_url
            else
              # TODO
              raise 'NOT VALIDATED' unless index_url == url
            end

            {
                :datetime => datetime,
                :url => url,
                :cache_partition => datetime.strftime("%Y/%m/%d-"),
                :valid_after => datetime + 1.day + 15.minutes
            }
          end


          def get_external_document(url)
            uri = URI(url)
            response = nil
            Net::HTTP.start(uri.host, uri.port) do |http|
              @log.debug(url)
              response = http.get(uri.path, {'Cookie' => get_authentication_cookies.join('; ')})
            end
            case response.code
              when '200'
                #when '302'
                #handle_set_cookie response['set-cookie'] unless response['set-cookie'].nil?
                #location = response['location']
                #filter_redirect_location location
                #return {:new_url => location}
                #when '404'
                #return {:unavailable => true}
              else
                p response
                raise "Fault Retrieve"
            end
            body = response.body
            body.force_encoding('UTF-8')
            raise 'Invalid UTF-8 Encoding of body' unless body.valid_encoding?
            yield body, {:document_version => EXTERNAL_DOCUMENT_VERSION}
          end

        end

      end
    end
  end
end
