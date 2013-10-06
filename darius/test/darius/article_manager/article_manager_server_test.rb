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

        def _test_client
          transport = Thrift::BufferedTransport.new(Thrift::Socket.new(@config[:remote_host], @config[:article_manager_server][:port].to_i))
          protocol = Thrift::BinaryProtocol.new(transport)
          client = ArticleManager::Client.new(protocol)
          transport.open
          begin
            request = GetDocumentRequest.new do |r|
              r.vendor = 'wsj'
              r.documentType = DocumentType::DAILY_ARCHIVE_INDEX
              r.flavor = DocumentFlavor::RAW
              r.outputType = OutputType::TEXT
            end
            p client.health
            p client.getDocument request
          ensure
            transport.close
          end
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
            begin
              server.start
            rescue Exception => e
              raise e
            end
          end

          sleep 2
          begin
            transport.open
            p client.health

            request = GetDocumentRequest.new do |r|
              r.vendor = 'wsj'
              r.documentType = DocumentType::DAILY_ARCHIVE_INDEX
              r.datetime = '2009-04-01T08:00:00Z'
              r.flavor = DocumentFlavor::PROCESSED_JSON
              r.outputType = OutputType::TEXT
            end

            result = client.getDocument request
            obj = JSON.parse result.document, :symbolize_names => true
            timestamp = result.timestamp
            obj[:articles].each do |article|
              request = GetDocumentRequest.new do |r|
                r.vendor = 'wsj'
                r.datetime = timestamp
                r.documentType = DocumentType::ARTICLE
                r.flavor = DocumentFlavor::PROCESSED_JSON
                r.documentUrl = article[:url]
                r.outputType = OutputType::S3_ARN
              end
              result = client.getDocument request
              p result
            end
          rescue ServiceException => se
            raise se
          ensure
            transport.close
            sleep 2
          end

          #  p result

        end

      end
    end
  end
end