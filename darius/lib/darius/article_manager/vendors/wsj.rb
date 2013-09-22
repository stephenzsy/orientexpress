require 'active_support/all'

require_relative '../article_vendor'

module ColdBlossom
  module Darius
    module ArticleManager
      module Vendors
        class WSJ < ArticleVendor
          VENDOR_NAME = 'wsj'

          Time.zone = 'America/New_York'

          def initialize
            super VENDOR_NAME
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
                :expire_before => datetime + 1.day + 15.minutes
            }
          end

        end

        WSJ.new.publish
      end
    end
  end
end
