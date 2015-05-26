require 'benchmark'
require 'dat-worker-pool'
require 'qs'
require 'qs/error_handler'
require 'qs/job'
require 'qs/logger'

module Qs

  class PayloadHandler

    attr_reader :daemon_data, :redis_item, :logger

    def initialize(daemon_data, redis_item)
      @daemon_data = daemon_data
      @redis_item  = redis_item
      @logger = Qs::Logger.new(
        @daemon_data.logger,
        @daemon_data.verbose_logging
      )
    end

    def run
      log_received
      benchmark = Benchmark.measure{ run!(@daemon_data, @redis_item) }
      @redis_item.time_taken = RoundedTime.new(benchmark.real)
      log_complete(@redis_item)
      raise_if_debugging!(@redis_item.exception)
    end

    private

    def run!(daemon_data, redis_item)
      redis_item.started = true

      payload = Qs.deserialize(redis_item.serialized_payload)
      job = Qs::Job.parse(payload)
      log_job(job)
      redis_item.job = job

      route = daemon_data.route_for(job.route_name)
      log_handler_class(route.handler_class)
      redis_item.handler_class = route.handler_class

      route.run(job, daemon_data)
      redis_item.finished = true
    rescue DatWorkerPool::ShutdownError => exception
      if redis_item.started
        error = ShutdownError.new(exception.message)
        error.set_backtrace(exception.backtrace)
        handle_exception(error, daemon_data, redis_item)
      end
      raise exception
    rescue StandardError => exception
      handle_exception(exception, daemon_data, redis_item)
    end

    def handle_exception(exception, daemon_data, redis_item)
      error_handler = Qs::ErrorHandler.new(exception, {
        :daemon_data        => daemon_data,
        :queue_redis_key    => redis_item.queue_redis_key,
        :serialized_payload => redis_item.serialized_payload,
        :job                => redis_item.job,
        :handler_class      => redis_item.handler_class
      }).tap(&:run)
      redis_item.exception = error_handler.exception
      log_exception(redis_item.exception)
    end

    def raise_if_debugging!(exception)
      raise exception if exception && ENV['QS_DEBUG']
    end

    def log_received
      log_verbose "===== Running job ====="
    end

    def log_job(job)
      log_verbose "  Job:     #{job.name.inspect}"
      log_verbose "  Params:  #{job.params.inspect}"
    end

    def log_handler_class(handler_class)
      log_verbose "  Handler: #{handler_class}"
    end

    def log_complete(redis_item)
      log_verbose "===== Completed in #{redis_item.time_taken}ms ====="
      summary_line_args = {
        'time'    => redis_item.time_taken,
        'handler' => redis_item.handler_class
      }
      if (job = redis_item.job)
        summary_line_args['job']    = job.name
        summary_line_args['params'] = job.params
      end
      if (exception = redis_item.exception)
        summary_line_args['error'] = "#{exception.inspect}"
      end
      log_summary SummaryLine.new(summary_line_args)
    end

    def log_exception(exception)
      backtrace = exception.backtrace.join("\n")
      message = "#{exception.class}: #{exception.message}\n#{backtrace}"
      log_verbose(message, :error)
    end

    def log_verbose(message, level = :info)
      self.logger.verbose.send(level, "[Qs] #{message}")
    end

    def log_summary(message, level = :info)
      self.logger.summary.send(level, "[Qs] #{message}")
    end

    module RoundedTime
      ROUND_PRECISION = 2
      ROUND_MODIFIER = 10 ** ROUND_PRECISION
      def self.new(time_in_seconds)
        (time_in_seconds * 1000 * ROUND_MODIFIER).to_i / ROUND_MODIFIER.to_f
      end
    end

    module SummaryLine
      def self.new(line_attrs)
        attr_keys = %w{time handler job params error}
        attr_keys.map{ |k| "#{k}=#{line_attrs[k].inspect}" }.join(' ')
      end
    end

  end

  ShutdownError = Class.new(DatWorkerPool::ShutdownError)

end
