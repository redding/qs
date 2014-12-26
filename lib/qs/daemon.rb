require 'ns-options'
require 'pathname'
require 'system_timer'
require 'thread'
require 'qs/daemon_data'
require 'qs/logger'
require 'qs/payload_handler'

module Qs

  module Daemon

    InvalidError = Class.new(ArgumentError)

    def self.included(klass)
      klass.class_eval do
        extend ClassMethods
        include InstanceMethods
      end
    end

    module InstanceMethods

      attr_reader :daemon_data, :logger

      def initialize
        self.class.configuration.validate!
        @daemon_data = DaemonData.new(self.class.configuration.to_hash)
        @logger = @daemon_data.logger

        @work_loop_thread = nil
        @worker_pool      = nil

        @signal = Signal.new(:stop)
      rescue InvalidError => exception
        exception.set_backtrace(caller)
        raise exception
      end

      def running?
        !!(@work_loop_thread && @work_loop_thread.alive?)
      end

      def start
        @signal.set :start
        @work_loop_thread ||= Thread.new{ work_loop }
      end

      def stop(wait = false)
        return unless self.running?
        @signal.set :stop
        wait_for_shutdown if wait
      end

      def halt(wait = false)
        return unless self.running?
        @signal.set :halt
        wait_for_shutdown if wait
      end

      private

      def process(serialized_payload)
        # TODO
      end

      def work_loop
        self.logger.debug "Starting work loop..."
        @worker_pool = DatWorkerPool.new(
          self.daemon_data.min_workers,
          self.daemon_data.max_workers
        ){ |serialized_payload| process(serialized_payload) }
        process_inputs while @signal.start?
        self.logger.debug "Stopping work loop..."
        shutdown_worker_pool unless @signal.halt?
      rescue StandardError => exception
        self.logger.error "Exception occurred, stopping daemon!"
        self.logger.error "#{exception.class}: #{exception.message}"
        self.logger.error exception.backtrace.join("\n")
      ensure
        @work_loop_thread = nil
        self.logger.debug "Stopped work loop"
      end

      def process_inputs
        sleep 1 # TODO
      end

      def shutdown_worker_pool
        self.logger.debug "Shutting down worker pool, letting it finish..."
        if self.daemon_data.shutdown_timeout
          shutdown_worker_pool_with_timeout(self.daemon_data.shutdown_timeout)
        else
          shutdown_worker_pool_without_timeout
        end
      end

      def shutdown_worker_pool_with_timeout(timeout)
        SystemTimer.timeout_after(timeout) do
          wait_for_worker_pool_to_empty
          @worker_pool.shutdown(timeout)
        end
      rescue Timeout::Error
        @worker_pool.shutdown(0)
      end

      def shutdown_worker_pool_without_timeout
        wait_for_worker_pool_to_empty
        @worker_pool.shutdown
      end

      def wait_for_worker_pool_to_empty
        sleep(5) while !@worker_pool.queue_empty? && !@signal.halt?
      end

      def wait_for_shutdown
        @work_loop_thread.join if @work_loop_thread
      end

    end

    module ClassMethods

      def configuration
        @configuration ||= Configuration.new
      end

      def name(*args)
        self.configuration.name(*args)
      end

      def pid_file(*args)
        self.configuration.pid_file(*args)
      end

      def min_workers(*args)
        self.configuration.min_workers(*args)
      end

      def max_workers(*args)
        self.configuration.max_workers(*args)
      end

      def workers(*args)
        self.min_workers(*args)
        self.max_workers(*args)
      end

      def verbose_logging(*args)
        self.configuration.verbose_logging(*args)
      end

      def logger(*args)
        self.configuration.logger(*args)
      end

      def shutdown_timeout(*args)
        self.configuration.shutdown_timeout(*args)
      end

      def init(&block)
        self.configuration.init_procs << block
      end

      def error(&block)
        self.configuration.error_procs << block
      end

      def queue(queue)
        self.configuration.queues << queue
      end

    end

    class Configuration
      include NsOptions::Proxy

      option :name,     String,  :required => true
      option :pid_file, Pathname

      option :min_workers, Integer, :default => 1
      option :max_workers, Integer, :default => 4

      option :verbose_logging, :default => true
      option :logger,          :default => proc{ Qs::NullLogger.new }

      option :shutdown_timeout

      attr_accessor :init_procs, :error_procs
      attr_accessor :queues

      def initialize(values = nil)
        super(values)
        @init_procs, @error_procs = [], []
        @queues = []
        @valid = nil
      end

      def routes
        @queues.map(&:routes).flatten
      end

      def to_hash
        super.merge({
          :error_procs => self.error_procs,
          :queue_redis_keys => self.queues.map(&:redis_key),
          :routes => self.routes
        })
      end

      def valid?
        !!@valid
      end

      def validate!
        return @valid if !@valid.nil?
        self.init_procs.each(&:call)
        if self.queues.empty? || !self.required_set?
          raise InvalidError, "a name and queue must be configured"
        end
        self.routes.each(&:validate!)
        @valid = true
      end
    end

    class Signal
      def initialize(value)
        @value = value
        @mutex = Mutex.new
      end

      def set(value)
        @mutex.synchronize{ @value = value }
      end

      def start?
        @mutex.synchronize{ @value == :start }
      end

      def stop?
        @mutex.synchronize{ @value == :stop }
      end

      def halt?
        @mutex.synchronize{ @value == :halt }
      end
    end

  end

end
