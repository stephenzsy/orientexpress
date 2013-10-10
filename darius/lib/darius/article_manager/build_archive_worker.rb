require_relative 'gen-rb/article_manager_types'

require_relative 'utils/async_worker'

module ColdBlossom
  module Darius
    module ArticleManager
      class BuildArchiveWorker
        extend ArticleManager::Utils::Worker

        set_config({:config => "this is config"})

        def perform(action, opt)
        end
      end
    end
  end
end