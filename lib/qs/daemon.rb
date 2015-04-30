require 'dat-worker-pool'
require 'ns-options'
require 'pathname'
require 'system_timer'
require 'thread'
require 'qs'
require 'qs/client'
require 'qs/daemon_data'
require 'qs/io_pipe'
require 'qs/logger'
require 'qs/payload_handler'
require 'qs/redis_item'

module Qs

  module Daemon

    InvalidError = Class.new(ArgumentError)

    SIGNAL = '.'.freeze

    def self.included(klass)
      klass.class_eval do
        extend ClassMethods
        include InstanceMethods
      end
    end

    module InstanceMethods

      attr_reader :daemon_data, :logger
      attr_reader :signals_redis_key, :queue_redis_keys

      # * Set the size of the client to the max workers + 1. This ensures we
      #   have 1 connection for fetching work from redis and at least 1
      #   connection for each worker to requeue its job when hard-shutdown.
      def initialize
        self.class.configuration.validate!
        Qs.init
        @daemon_data = DaemonData.new(self.class.configuration.to_hash)
        @logger = @daemon_data.logger

        @client = QsClient.new(Qs.redis_config.merge({
          :timeout => 1,
          :size    => self.daemon_data.max_workers + 1
        }))
        @queue_redis_keys = self.daemon_data.queue_redis_keys

        @work_loop_thread = nil
        @worker_pool      = nil

        @signals_redis_key = "signals:#{@daemon_data.name}-" \
                             "#{Socket.gethostname}-#{::Process.pid}"

        @worker_available_io = IOPipe.new
        @signal = Signal.new(:stop)
      rescue InvalidError => exception
        exception.set_backtrace(caller)
        raise exception
      end

      def name
        @daemon_data.name
      end

      def pid_file
        @daemon_data.pid_file
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
        wakeup_work_loop_thread
        wait_for_shutdown if wait
      end

      def halt(wait = false)
        return unless self.running?
        @signal.set :halt
        wakeup_work_loop_thread
        wait_for_shutdown if wait
      end

      private

      def process(redis_item)
        Qs::PayloadHandler.new(self.daemon_data, redis_item).run
      end

      def work_loop
        log "Starting work loop", :debug
        setup_redis_and_ios
        @worker_pool = build_worker_pool
        process_inputs while @signal.start?
        log "Stopping work loop", :debug
      rescue StandardError => exception
        @signal.set :stop
        log "Error occurred while running the daemon, exiting", :error
        log "#{exception.class}: #{exception.message}", :error
        log exception.backtrace.join("\n"), :error
      ensure
        shutdown_worker_pool
        @worker_available_io.teardown
        @work_loop_thread = nil
        log "Stopped work loop", :debug
      end

      def setup_redis_and_ios
        # clear any signals that are already on the signals redis list
        @client.clear(self.signals_redis_key)
        @worker_available_io.setup
      end

      def build_worker_pool
        wp = DatWorkerPool.new(
          self.daemon_data.min_workers,
          self.daemon_data.max_workers
        ){ |redis_item| process(redis_item) }
        wp.on_worker_error do |worker, exception, redis_item|
          handle_worker_exception(exception, redis_item)
        end
        wp.on_worker_sleep{ @worker_available_io.write(SIGNAL) }
        wp.start
        wp
      end

      # * Shuffle the queue redis keys to avoid queue starvation. Redis will
      #   pull jobs off queues in the order they are passed to the command, by
      #   shuffling we ensure they are randomly ordered so every queue should
      #   get a chance.
      # * Use 0 for the brpop timeout which means block indefinitely.
      # * Rescue runtime errors so the daemon thread doesn't fail if redis is
      #   temporarily down. Sleep for a second to keep the thread from thrashing
      #   by repeatedly erroring if redis is down.
      def process_inputs
        wait_for_available_worker
        return unless @worker_pool.worker_available? && @signal.start?

        begin
          args = [self.signals_redis_key, self.queue_redis_keys.shuffle, 0].flatten
          redis_key, serialized_payload = @client.block_dequeue(*args)
          if redis_key != @signals_redis_key
            @worker_pool.add_work(RedisItem.new(redis_key, serialized_payload))
          end
        rescue RuntimeError => exception
          log "Error dequeueing #{exception.message.inspect}", :error
          log exception.backtrace.join("\n"), :error
          sleep 1
        end
      end

      def wait_for_available_worker
        if !@worker_pool.worker_available? && @signal.start?
          @worker_available_io.wait.read
        end
      end

      def shutdown_worker_pool
        return unless @worker_pool
        timeout = @signal.stop? ? self.daemon_data.shutdown_timeout : 0
        if timeout
          log "Shutting down, waiting up to #{timeout} seconds for work to finish"
        else
          log "Shutting down, waiting for work to finish"
        end
        @worker_pool.shutdown(timeout)
        log "Requeueing #{@worker_pool.work_items.size} job(s)"
        @worker_pool.work_items.each do |ri|
          @client.prepend(ri.queue_redis_key, ri.serialized_payload)
        end
      end

      def wait_for_shutdown
        @work_loop_thread.join if @work_loop_thread
      end

      def wakeup_work_loop_thread
        @client.append(self.signals_redis_key, SIGNAL)
        @worker_available_io.write(SIGNAL)
      end

      # * This only catches errors that happen outside of running the payload
      #   handler. The only known use-case for this is dat worker pools
      #   hard-shutdown errors.
      # * If there isn't a redis item (this can happen when an idle worker is
      #   being forced to exit) then we don't need to do anything.
      # * If we never started processing the redis item, its safe to requeue it.
      #   Otherwise it happened while processing so the payload handler caught
      #   it or it happened after the payload handler which we don't care about.
      def handle_worker_exception(exception, redis_item)
        return if redis_item.nil?
        if !redis_item.started
          log "Worker error, requeueing job because it hasn't started", :error
          @client.prepend(redis_item.queue_redis_key, redis_item.serialized_payload)
        else
          log "Worker error after job was processed, ignoring", :error
        end
        log "#{exception.class}: #{exception.message}", :error
        log exception.backtrace.join("\n"), :error
      end

      def log(message, level = :info)
        self.logger.send(level, "[Qs] #{message}")
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
          :error_procs      => self.error_procs,
          :queue_redis_keys => self.queues.map(&:redis_key),
          :routes           => self.routes
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
