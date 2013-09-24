require 'test/unit'

require 'thrift'
require 'darius/article_manager/gen-rb/article_manager'

require 'darius/article_manager/utils/configuration_util'
require 'darius/article_manager/article_manager_handler'
require 'darius/article_manager/article_manager_server'

module ColdBlossom
  module Darius
    module ArticleManager
      class ArticleManagerServerTest < Test::Unit::TestCase

        # Called before every test method runs. Can be used
        # to set up fixture information.
        def setup
          @config = ArticleManager::Utils::ConfigurationUtil.load_config_from_file File.join(File.expand_path(File.dirname(__FILE__)), 'darius-config.yml')
        end

        # Called after every test method runs. Can be used to tear
        # down fixture information.

        def teardown
          # Do nothing
        end

        def test_start_server
          server = ArticleManagerServer.new @config

          # client code - begin
          transport = Thrift::BufferedTransport.new(Thrift::Socket.new('localhost', @config[:article_manager_server][:port].to_i))
          protocol = Thrift::BinaryProtocol.new(transport)
          client = ArticleManager::Client.new(protocol)
          # client code - end

          #client = ThriftClient.new ArticleManager::Client, "localhost:#{@config[:article_manager_server][:port]}", :retries => 2
          thread = Thread.new do
            #server.start
          end
          request = GetDocumentRequest.new do |r|
            r.vendor = 'wsj'
            r.documentType = DocumentType::DAILY_ARCHIVE_INDEX
            r.flavor = DocumentFlavor::RAW
          end

          #  handler = ArticleManagerHandler.new @config
          #  result = handler.getDocument request
          t = Thread.new do
            sleep 2
            transport.open
            p client.health
            p client.getDocument(request)
          end
          t.join
          #  p result

        end

      end
    end
  end
end