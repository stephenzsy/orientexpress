require 'thrift'
require_relative 'article_manager_handler'

module ColdBlossom
  module Darius
    module ArticleManager
      class ArticleManagerServer
        def initialize(config)
          @handler = ArticleManagerHandler.new config
          @port = config[:article_manager_server][:port].to_i
        end

        def start
          processor = Processor.new(@handler)
          transport = Thrift::ServerSocket.new(@port)
          transport_factory = Thrift::BufferedTransportFactory.new
          protocol_factory = Thrift::BinaryProtocolFactory.new
          server = Thrift::ThreadPoolServer.new processor, transport, transport_factory, protocol_factory
          puts "Starting the Article Manager server..."
          server.serve()
          puts "done."
        end
      end
    end
  end
end
