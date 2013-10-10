require_relative 'gen-rb/article_manager_types'

require_relative 'utils/async_worker'

module ColdBlossom
  module Darius
    module ArticleManager
      class BuildArchiveWorker
        extend ArticleManager::Utils::WorkerClient
        include ArticleManager::Utils::WorkerServer

        def perform(action, params)
          p action

          p params
        end
      end
    end
  end
end