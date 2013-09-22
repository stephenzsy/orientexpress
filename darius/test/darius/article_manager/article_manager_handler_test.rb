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

        def test_getOriginalDocumentDefault
          request = GetOriginalDocumentRequest.new do |r|
            r.vendor = 'wsj'
            r.documentType = DocumentType::DAILY_ARCHIVE_INDEX
          end

          handler = ArticleManagerHandler.new @config
          handler.getOriginalDocument request

        end

      end
    end
  end
end