require 'test/unit'

require 'darius/article_manager/article_manager_handler'

module ColdBlossom
  module Darius
    module ArticleManager
      class ArticleManagerHandlerTest < Test::Unit::TestCase

        # Called before every test method runs. Can be used
        # to set up fixture information.
        def setup
          # Do nothing
        end

        # Called after every test method runs. Can be used to tear
        # down fixture information.

        def teardown
          # Do nothing
        end

        def test_getOriginalDocumentDefault
          request = GetOriginalDocumentRequest.new
          request.vendor = 'wsj'
          request.documentType = DocumentType::DAILY_ARCHIVE_INDEX
          ArticleManagerHandler.new.getOriginalDocument request

          p ArticleManagerHandler.new.version
        end

      end
    end
  end
end