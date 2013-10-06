require 'test/unit'

require 'darius/article_manager/utils/configuration_util'
require 'darius/article_manager/article_manager_handler'

module ColdBlossom
  module Darius
    module ArticleManager
      class ArticleManagerHandlerTest < Test::Unit::TestCase

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

        def _test_getDocument_default
          request = GetDocumentRequest.new do |r|
            r.vendor = 'wsj'
            r.documentType = DocumentType::DAILY_ARCHIVE_INDEX
            r.flavor = DocumentFlavor::RAW
            r.outputType = OutputType::TEXT
          end

          handler = ArticleManagerHandler.new @config
          result = handler.getDocument request
          p result

        end

        def _test_getDocument_article
          request = GetDocumentRequest.new do |r|
            r.vendor = 'wsj'
            r.documentType = DocumentType::DAILY_ARCHIVE_INDEX
            r.datetime = '2009-04-01T08:00:00Z'
            r.flavor = DocumentFlavor::PROCESSED_JSON
            r.outputType = OutputType::TEXT
          end

          handler = ArticleManagerHandler.new @config
          result = handler.getDocument request
          obj = JSON.parse result.document, :symbolize_names => true
          timestamp = result.timestamp
          obj[:articles].each do |article|
            request = GetDocumentRequest.new do |r|
              r.vendor = 'wsj'
              r.datetime = timestamp
              r.documentType = DocumentType::ARTICLE
              r.flavor = DocumentFlavor::PROCESSED_JSON
              r.documentUrl = article[:url]
              r.outputType = OutputType::TEXT
            end
            result = handler.getDocument request
            p result
          end
        end


        def _test_getDocument_processed_json
          request = GetDocumentRequest.new do |r|
            r.vendor = 'wsj'
            r.documentType = DocumentType::DAILY_ARCHIVE_INDEX
            r.flavor = DocumentFlavor::PROCESSED_JSON
            r.outputType = OutputType::TEXT
          end

          handler = ArticleManagerHandler.new @config
          result = handler.getDocument request
          p result

        end

        def _test_getDocument_past
          request = GetDocumentRequest.new do |r|
            r.vendor = 'wsj'
            r.documentType = DocumentType::DAILY_ARCHIVE_INDEX
            r.flavor = DocumentFlavor::RAW
            r.datetime = Time.parse('2011-02-01').iso8601
            r.cacheOption = CacheOption::REFRESH
          end

          handler = ArticleManagerHandler.new @config
          result = handler.getDocument request
          p result

        end


        def _test_getDocument_past2
          request = GetDocumentRequest.new do |r|
            r.vendor = 'wsj'
            r.documentType = DocumentType::DAILY_ARCHIVE_INDEX
            r.flavor = DocumentFlavor::RAW
            r.datetime = Time.parse('2011-02-01').iso8601
            r.cacheOption = CacheOption::DEFAULT
          end

          handler = ArticleManagerHandler.new @config
          result = handler.getDocument request
          p result

          request.outputType = OutputType::TEXT
          result = handler.getDocument request

          # p result

        end

      end
    end
  end
end