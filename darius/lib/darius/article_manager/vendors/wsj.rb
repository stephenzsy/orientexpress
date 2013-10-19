require 'active_support/all'
require 'nokogiri'

require_relative '../article_vendor'
require_relative '../utils/cookie_helper'

require_relative 'wsj/wsj_parsers_v20130923'
require_relative 'wsj/wsj_parsers_v20131019'

module ColdBlossom
  module Darius
    module ArticleManager
      module Vendors
        class WSJ < ArticleVendor
          include ArticleManager::Utils::CookieHelper
          include ArticleManager::Utils::DynamoDBCookieStore

          VENDOR_NAME = 'wsj'

          TIME_ZONE = ActiveSupport::TimeZone['America/New_York']

          EXTERNAL_DOCUMENT_VERSION = '2013-10-19'

          ARTICLE_PARSERS = {
              '2013-09-23' => VendorParsers::WSJ::V20130923::ArticleParser.new,
              '2013-10-19' => VendorParsers::WSJ::V20131019::ArticleParser.new,
              :default => VendorParsers::WSJ::V20131019::ArticleParser.new
          }

          def initialize(config)
            @log = Logger.new(STDOUT)
            @log.level = Logger::DEBUG
            self.allowed_document_versions = ['2013-10-19']

            super VENDOR_NAME
            set_cookie_store config, self
            set_authentication_cookies(get_stored_cookies())
          end

          def get_archive_info(date_str)
            date = Time.parse(date_str).in_time_zone(TIME_ZONE).midnight
            {
                :cache_partition => date.strftime("%Y/%m/%d-"),
                :date => date,
                :valid_after => date + 1.day + 15.minutes
            }
          end


          def get_archive_index_info datetime, url = nil
            datetime = datetime.in_time_zone(TIME_ZONE).midnight
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

          def get_article_info(datetime, url)
            datetime = datetime.in_time_zone TIME_ZONE
            {
                :datetime => datetime,
                :url => url,
                :cache_partition => datetime.strftime("%Y/%m/%d/")
            }
          end

          def handle_set_cookie(set_cookie_line)
            cookies = {}
            set_cookie_line.split(/,\s*/).each do |cookie_line|
              if cookie_line.match /^(?<name>djcs_\w+)=(?<value>[^;]*)/
                cookies[$~[:name]] = $~[:value]
              elsif cookie_line.match /^user_type=subscribed/
                cookies['user_type'] = 'subscribed'
              end
            end
            if (cookies['djcs_auto'] and cookies['djcs_perm'] and cookies['djcs_session'] and cookies['user_type'])
              yield [
                  "djcs_auto=#{cookies['djcs_auto']}",
                  "djcs_perm=#{cookies['djcs_perm']}",
                  "djcs_session=#{cookies['djcs_session']}",
                  "user_type=#{cookies['user_type']}"
              ]
            end
          end

          def get_external_document(url)
            1.upto(5) do
              uri = URI(url)
              response = nil
              http = Net::HTTP.new(uri.host, uri.port)
              http.use_ssl = (uri.scheme == 'https')
              @log.debug(url)
              http.start do |http|
                response = http.get(uri.path, {'Cookie' => get_authentication_cookies.join('; ')})
              end
              case response.code
                when '200'
                when '301'
                  url = response['location']
                  raise 'Invalid location' unless URI.parse(url).host().end_with? 'wsj.com'
                  next
                when '302'
                  unless response['set-cookie'].nil?
                    handle_set_cookie response['set-cookie'] do |cookies|
                      put_stored_cookies cookies
                      set_authentication_cookies cookies
                    end
                  end
                  url = response['location']
                  raise 'Invalid location' unless URI.parse(url).host().end_with? 'wsj.com'
                  next
                else
                  p response
                  raise "Fault Retrieve"
              end
              @log.debug("request DONE")
              body = response.body
              body.force_encoding('UTF-8')
              raise 'Invalid UTF-8 Encoding of body' unless body.valid_encoding?
              yield body, {:document_version => EXTERNAL_DOCUMENT_VERSION}
              break
            end
          end

          def daily_archive_index_to_json(document)
            result = {
                :articles => [],
            }
            doc = Nokogiri::HTML(document)
            archived_articles = doc.css('#archivedArticles')
            news_item = archived_articles.css('ul.newsItem')
            news_item.css('li').each do |item|
              a = item.css('a').first
              p = item.css('p').first
              url = a['href']
              a.remove
              result[:articles] << {
                  :url => url,
                  :title => a.text.strip,
                  :summary => p.text
              }
            end
            yield result, {:document_version => EXTERNAL_DOCUMENT_VERSION, :processor_version => DAILY_ARCHIVE_INDEX_PROCESSOR_VERSION}
          end

          def article_to_json(url, document)
            r = {}

            if url.start_with? 'http://graphicsweb.wsj.com'
              r = {:domain => 'graphicsweb.wsj.com', :url => url}
            else
              fix_article_html! document
              doc = Nokogiri::HTML(document)
              p url
              r = ARTICLE_PARSERS[:default].parse(doc)
              r[:url] = url
            end

            yield r, {:document_version => EXTERNAL_DOCUMENT_VERSION, :processor_version => ARTICLE_PROCESSOR_VERSION, :processor_patch => ARTICLE_PROCESSOR_PATCH}
          end


          private
          def get_archive_index_url datetime
            "http://online.wsj.com/public/page/archive-#{datetime.strftime "%Y-%-m-%-d"}.html"
          end


          def fix_article_html!(text)
            text.gsub!('<TH>', ' ')
          end
        end
      end
    end
  end
end
