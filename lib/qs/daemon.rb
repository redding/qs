require 'dat-worker-pool'
require 'ns-options'
require 'pathname'
require 'system_timer'
require 'thread'
require 'qs'
require 'qs/client'
require 'qs/daemon_data'
require 'qs/logger'
require 'qs/queue_item'
require 'qs/worker'

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
      #   connection for each worker to requeue its message when hard-shutdown.
      def initialize
        self.class.configuration.validate!
        Qs.init
        @daemon_data = DaemonData.new(self.class.configuration.to_hash)
        @logger = @daemon_data.logger

        @client = QsClient.new(Qs.redis_config.merge({
          :timeout => 1,
          :size    => self.daemon_data.num_workers + 1
        }))
        @queue_redis_keys = self.daemon_data.queue_redis_keys

        @signals_redis_key = "signals:#{@daemon_data.name}-" \
                             "#{Socket.gethostname}-#{::Process.pid}"

        @worker_available = WorkerAvailable.new

        @worker_pool = DatWorkerPool.new(self.daemon_data.worker_class, {
          :num_workers   => self.daemon_data.num_workers,
          :worker_params => self.daemon_data.worker_params.merge({
            :qs_daemon_data      => self.daemon_data,
            :qs_client           => @client,
            :qs_worker_available => @worker_available,
            :qs_logger           => @logger
          })
        })

        @thread = nil
        @signal = Signal.new(:stop)
      rescue InvalidError => exception
        exception.set_backtrace(caller)
        raise exception
      end

      def name
        @daemon_data.name
      end

      def process_label
        @daemon_data.process_label
      end

      def pid_file
        @daemon_data.pid_file
      end

      def running?
        !!(@thread && @thread.alive?)
      end

      # * Ping redis to check that it can communicate with redis before running,
      #   this is friendlier than starting and continously erroring because it
      #   can't dequeue.
      def start
        @client.ping
        @signal.set :start
        @thread ||= Thread.new{ work_loop }
      end

      def stop(wait = false)
        return unless self.running?
        @signal.set :stop
        wakeup_thread
        wait_for_shutdown if wait
      end

      def halt(wait = false)
        return unless self.running?
        @signal.set :halt
        wakeup_thread
        wait_for_shutdown if wait
      end

      private

      def work_loop
        setup
        fetch_messages while @signal.start?
      rescue StandardError => exception
        @signal.set :stop
        log "Error occurred while running the daemon, exiting", :error
        log "#{exception.class}: #{exception.message}", :error
        log exception.backtrace.join("\n"), :error
      ensure
        teardown
      end

      def setup
        log "Starting work loop", :debug
        # clear any signals that are already on the signals list
        @client.clear(self.signals_redis_key)
        @worker_pool.start
      end

      # * Shuffle the queue redis keys to avoid queue starvation. Redis will
      #   pull messages off queues in the order they are passed to the command,
      #   by shuffling we ensure they are randomly ordered so every queue should
      #   get a chance.
      # * Use 0 for the brpop timeout which means block indefinitely.
      # * Rescue runtime errors so the daemon thread doesn't fail if redis is
      #   temporarily down. Sleep for a second to keep the thread from thrashing
      #   by repeatedly erroring if redis is down.
      def fetch_messages
        if !@worker_pool.worker_available? && @signal.start?
          @worker_available.wait
        end
        return unless @worker_pool.worker_available? && @signal.start?

        begin
          args = [self.signals_redis_key, self.queue_redis_keys.shuffle, 0].flatten
          redis_key, encoded_payload = @client.block_dequeue(*args)
          if redis_key != @signals_redis_key
            @worker_pool.push(QueueItem.new(redis_key, encoded_payload))
          end
        rescue RuntimeError => exception
          log "Error dequeueing #{exception.message.inspect}", :error
          log exception.backtrace.join("\n"), :error
          sleep 1
        end
      end

      def teardown
        log "Stopping work loop", :debug

        timeout = @signal.halt? ? 0 : self.daemon_data.shutdown_timeout
        @worker_pool.shutdown(timeout)

        log "Requeueing #{@worker_pool.work_items.size} message(s)"
        @worker_pool.work_items.each do |qi|
          @client.prepend(qi.queue_redis_key, qi.encoded_payload)
        end

        log "Stopped work loop", :debug
      ensure
        @thread = nil
      end

      def wakeup_thread
        @client.append(self.signals_redis_key, SIGNAL)
        @worker_available.signal
      end

      def wait_for_shutdown
        @thread.join if @thread
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

      def worker_class(new_worker_class = nil)
        self.configuration.worker_class = new_worker_class if new_worker_class
        self.configuration.worker_class
      end

      def worker_params(new_worker_params = nil )
        self.configuration.worker_params = new_worker_params if new_worker_params
        self.configuration.worker_params
      end

      def num_workers(*args)
        self.configuration.num_workers(*args)
      end
      alias :workers :num_workers

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

      option :num_workers, Integer, :default => 4

      option :verbose_logging, :default => true
      option :logger,          :default => proc{ Qs::NullLogger.new }

      option :shutdown_timeout

      attr_accessor :init_procs, :error_procs
      attr_accessor :worker_class, :worker_params
      attr_accessor :queues

      def initialize(values = nil)
        super(values)
        @init_procs, @error_procs = [], []
        @worker_class  = DefaultWorker
        @worker_params = nil
        @queues = []
        @valid = nil
      end

      def routes
        @queues.map(&:routes).flatten
      end

      def to_hash
        super.merge({
          :error_procs      => self.error_procs,
          :worker_class     => self.worker_class,
          :worker_params    => self.worker_params,
          :routes           => self.routes,
          :queue_redis_keys => self.queues.map(&:redis_key)
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
        if !self.worker_class.kind_of?(Class) || !self.worker_class.include?(Qs::Worker)
          raise InvalidError, "worker class must include `#{Qs::Worker}`"
        end
        self.routes.each(&:validate!)
        @valid = true
      end
    end

    DefaultWorker = Class.new{ include Qs::Worker }

    class WorkerAvailable
      def initialize
        @mutex = Mutex.new
        @cv    = ConditionVariable.new
      end

      def wait
        @mutex.synchronize{ @cv.wait(@mutex) }
      end

      def signal
        @mutex.synchronize{ @cv.signal }
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
