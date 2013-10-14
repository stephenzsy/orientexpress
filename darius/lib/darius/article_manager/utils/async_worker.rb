require 'monitor'

require_relative 'configuration_util'
require_relative '../article_manager_base_client'

module ColdBlossom
  module Darius
    module ArticleManager
      module Utils

        class AsyncWorkManager

          def initialize(config, queue)
            @sqs = AWS::SQS.new ConfigurationUtil.configure_aws config
            @queue_info = config[:queues][queue]
            @sqs_queue = @sqs.queues[@queue_info[:sqs_queue_url]]
          end

          def submit(action, params, opt={})
            message_obj = {:action => action, :params => params, :opt => {}}
            message_obj[:opt][:retry_count] = opt[:retry_count] unless opt[:retry_count].nil?
            message_obj[:opt][:max_retry] = opt[:max_retry] unless opt[:max_retry].nil?
            message_obj[:opt][:origin_time] = opt[:origin_time].utc.iso8601
            @sqs_queue.send_message(JSON.generate(message_obj))
          end

          def poll
            begin
              message = @sqs_queue.receive_message
              return nil if message.nil?
              obj = JSON.parse message.body, :symbolize_names => true
              obj[:opt][:origin_time] = Time.parse obj[:opt][:origin_time] unless obj[:opt].nil? or obj[:opt][:origin_time].nil?
              obj
            ensure
              message.delete if message
            end
          end
        end

        module Worker
          DEFAULT_MAX_RETRY = 3

          def set_config(config, opt)
            return unless @manager.nil? or opt[:force]
            @manager = AsyncWorkManager.new config, opt[:queue]
            @article_manager_client = ArticleManager::ArticleManagerBaseClient.new config[:remote_host], config[:article_manager_server][:port].to_i
            @cache_manager = ArticleManager::S3CacheManager.new config
          end

        end

        module WorkerClient
          include Worker

          def perform_async(action, params, opt = {})
            opt[:origin_time] ||= Time.now
            @manager.submit(action, params, opt)
            p opt
          end
        end

        module WorkerServer
          include Worker

          class WorkerException < StandardError

          end

          def perform(action, params)
            send action, params
          end

          def start_worker(opt = {})
            thread_pool = []
            work_done = 0
            opt[:num_thread] ||= 1
            max_work = opt[:max_work_unit]
            max_work ||= 0

            1.upto(opt[:num_thread]) do
              thread_pool << Thread.new do
                while (true)
                  #poll sqs
                  work = @manager.poll
                  next if work.nil?
                  work[:action] = work[:action].to_sym
                  work_opt = work[:opt]
                  work_opt ||= {}
                  p work
                  max_retry = work_opt[:max_retry]
                  max_retry ||= DEFAULT_MAX_RETRY
                  begin
                    status, next_work = perform(work[:action], work[:params])
                    case status
                      when :fail # fail, retry with default limit
                        work_opt[:retry_count] = work_opt[:retry_count].nil? ? 1 : work_opt[:retry_count] + 1
                        self.class.perform_async(work[:action], work[:params], work_opt) if work_opt[:retry_count] < max_retry
                      when :retry # forced retry, disregard of retry limit
                        work_opt[:retry_count] = work_opt[:retry_count].nil? ? 1 : work_opt[:retry_count] + 1
                        self.class.perform_async(work[:action], work[:params], work_opt)
                      when :terminate # forced terminate, will not retry
                      else
                        # treat like success
                        #  self.class.perform_async(next_work[:action], next_work[:params], next_work[:opt]) unless next_work.nil?
                    end
                    work_done += 1
                    p work_done
                    break if max_work == 0 or work_done >= max_work
                  rescue Exception => e
                    # Any exception treat as fail, default retry
                    p work_opt
                    work_opt[:retry_count] = work_opt[:retry_count].nil? ? 1 : work_opt[:retry_count] + 1
                    self.class.perform_async(work[:action], work[:params], work_opt) if work_opt[:retry_count] < max_retry
                  end
                end
              end
            end
            thread_pool.each do |thread|
              thread.join
            end
          end
        end

      end
    end
  end
end
