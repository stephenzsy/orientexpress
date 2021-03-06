require_relative 'configuration_util'

module ColdBlossom
  module Darius
    module ArticleManager
      module Utils
        module CookieHelper
          def set_authentication_cookies(cookies)
            @auth_cookies = cookies.to_a
          end

          def get_authentication_cookies
            @auth_cookies
          end
        end

        module DynamoDBCookieStore

          def set_cookie_store(config, vendor)
            @dynamoDB = AWS::DynamoDB.new ConfigurationUtil.configure_aws config
            @cookies_key = config[:vendor][vendor.name][:state_table_key_authentication_cookies]
            @state_table = @dynamoDB.tables[config[:state_table][:table_name]]
            @state_table.load_schema
          end

          def get_stored_cookies
            @state_table.items[@cookies_key].attributes['value']
          end

          def put_stored_cookies(cookies)
            @state_table.items[@cookies_key].attributes['value'] = cookies
            @state_table.items[@cookies_key].attributes['last_updated'] = Time.now.utc.iso8601
          end
        end
      end
    end
  end
end