require 'dat-worker-pool'
require 'hella-redis'
require 'ns-options'
require 'pathname'
require 'system_timer'
require 'thread'
require 'qs'
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
      attr_reader :signals_redis_key, :queue_redis_keys

      def initialize
        self.class.configuration.validate!
        Qs.init
        @daemon_data = DaemonData.new(self.class.configuration.to_hash)
        @logger = @daemon_data.logger

        @redis = HellaRedis::Connection.new(Qs.redis_config.merge({
          :timeout => 1,
          :size    => 2
        }))
        @queue_redis_keys = self.daemon_data.queue_redis_keys

        @work_loop_thread = nil
        @worker_pool      = nil

        @signals_redis_key = "signals:#{@daemon_data.name}-" \
                             "#{Socket.gethostname}-#{::Process.pid}"

        @worker_available_io = IOPipe.new
        @queue_pop_io        = IOPipe.new

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
        Qs::PayloadHandler.new(
          self.daemon_data,
          redis_item.queue_key,
          redis_item.serialized_payload
        ).run
      end

      def work_loop
        self.logger.debug "Starting work loop..."
        setup_redis_and_ios
        @worker_pool = build_worker_pool
        process_inputs while @signal.start?
        self.logger.debug "Stopping work loop..."
        shutdown_worker_pool unless @signal.halt?
      rescue StandardError => exception
        self.logger.error "Exception occurred, stopping daemon!"
        self.logger.error "#{exception.class}: #{exception.message}"
        self.logger.error exception.backtrace.join("\n")
      ensure
        @worker_available_io.teardown
        @queue_pop_io.teardown
        @work_loop_thread = nil
        self.logger.debug "Stopped work loop"
      end

      def setup_redis_and_ios
        # the 0 is the timeout for the `brpop` command, 0 means block indefinitely
        @brpop_args = [self.signals_redis_key, self.queue_redis_keys, 0].flatten
        # clear any signals that are already on the signals redis list
        @redis.with{ |c| c.del(self.signals_redis_key) }

        @worker_available_io.setup
        @queue_pop_io.setup
      end

      def build_worker_pool
        wp = DatWorkerPool.new(
          self.daemon_data.min_workers,
          self.daemon_data.max_workers
        ){ |redis_item| process(redis_item) }
        wp.on_queue_pop{ @queue_pop_io.signal }
        wp.on_worker_sleep{ @worker_available_io.signal }
        wp.start
        wp
      end

      def process_inputs
        wait_for_available_worker
        return unless @worker_pool.worker_available? && @signal.start?
        redis_key, serialized_payload = @redis.with{ |c| c.brpop(*@brpop_args) }
        if redis_key != @signals_redis_key
          @worker_pool.add_work(RedisItem.new(redis_key, serialized_payload))
        end
      end

      def wait_for_available_worker
        if !@worker_pool.worker_available? && @signal.start?
          @worker_available_io.wait
        end
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
        while !@worker_pool.queue_empty? && !@signal.halt?
          @queue_pop_io.wait
        end
      end

      def wait_for_shutdown
        @work_loop_thread.join if @work_loop_thread
      end

      def wakeup_work_loop_thread
        @redis.with{ |c| c.lpush(self.signals_redis_key, '.') }
        @worker_available_io.signal
        @queue_pop_io.signal
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

    RedisItem = Struct.new(:queue_key, :serialized_payload)

    class IOPipe
      NULL   = File.open('/dev/null', 'w')
      SIGNAL = '.'.freeze

      attr_reader :reader, :writer

      def initialize
        @reader = NULL
        @writer = NULL
      end

      def wait
        ::IO.select([@reader])
        @reader.read_nonblock(SIGNAL.bytesize)
      end

      def signal
        @writer.write_nonblock(SIGNAL)
      end

      def setup
        @reader, @writer = ::IO.pipe
      end

      def teardown
        @reader.close
        @writer.close
        @reader = NULL
        @writer = NULL
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
