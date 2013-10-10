require 'monitor'

require_relative 'configuration_util'

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
            message_obj = {:action => action, :params => params}
            message_obj[:retry_count] = opt[:retry_count] unless opt[:retry_count].nil?
            message_obj[:max_retry] = opt[:max_retry] unless opt[:max_retry].nil?
            @sqs_queue.send_message(JSON.generate(message_obj))
          end

          def poll
            begin
              message = @sqs_queue.receive_message
              JSON.parse message.body, :symbolize_names => true
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
          end

        end

        module WorkerClient
          include Worker

          def perform_async(action, params, opt = {})
            @manager.submit(action, params, opt)
            p opt
          end
        end

        module WorkerServer
          include Worker

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
                  begin
                    result = perform(work[:action], work[:params])
                    case result
                      when :success
                      when :fail
                      when :retry # forced retry
                      when :terminate # forced terminate
                      else
                        # treat like success
                    end
                    work_done += 1
                    p work_done
                    break if max_work == 0 or work_done >= max_work
                  rescue Exception => e
                    # Any exception treat as fail, default retry
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
