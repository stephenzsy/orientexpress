require 'thrift'
require 'monitor'

require_relative 'gen-rb/article_manager'

module ColdBlossom
  module Darius
    module ArticleManager
      class ArticleManagerBaseClient < Monitor

        def initialize(host, port)
          @host = host
          @port = port
        end

        def method_missing(m, *args, &block)
          case m
            when :health, :getDocument
              transport =  Thrift::BufferedTransport.new Thrift::Socket.new(@host, @port)
              protocol = Thrift::BinaryProtocol.new(transport)
              client = ArticleManager::Client.new(protocol)
              begin
                transport.open
                return client.send m, *args, &block
              ensure
                transport.close
              end
          end
        end

      end
    end
  end
end