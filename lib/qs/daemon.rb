require 'dat-worker-pool'
require 'much-plugin'
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
    include MuchPlugin

    SIGNAL = '.'.freeze

    plugin_included do
      extend ClassMethods
      include InstanceMethods
    end

    module InstanceMethods

      attr_reader :daemon_data, :signals_redis_key

      def initialize
        config = self.class.config
        begin
          config.validate!
        rescue InvalidError => exception
          exception.set_backtrace(caller)
          raise exception
        end
        Qs.init

        @daemon_data = DaemonData.new({
          :name             => config.name,
          :pid_file         => config.pid_file,
          :shutdown_timeout => config.shutdown_timeout,
          :worker_class     => config.worker_class,
          :worker_params    => config.worker_params,
          :num_workers      => config.num_workers,
          :error_procs      => config.error_procs,
          :logger           => config.logger,
          :queues           => config.queues,
          :verbose_logging  => config.verbose_logging,
          :routes           => config.routes
        })

        @signals_redis_key = "signals:#{self.daemon_data.name}-" \
                             "#{Socket.gethostname}-#{::Process.pid}"

        @thread           = nil
        @worker_available = WorkerAvailable.new
        @state            = State.new(:stop)

        # set the size of the client to the num workers + 1, this ensures we
        # have 1 connection for fetching work from redis and at least 1
        # connection for each worker to requeue its message when hard-shutdown
        @client = QsClient.new(Qs.redis_connect_hash.merge({
          :timeout => 1,
          :size    => self.daemon_data.num_workers + 1
        }))

        @worker_pool = DatWorkerPool.new(self.daemon_data.worker_class, {
          :num_workers   => self.daemon_data.num_workers,
          :logger        => self.daemon_data.dwp_logger,
          :worker_params => self.daemon_data.worker_params.merge({
            :qs_daemon_data      => self.daemon_data,
            :qs_client           => @client,
            :qs_worker_available => @worker_available,
            :qs_logger           => self.logger
          })
        })
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

      def logger
        @daemon_data.logger
      end

      def queue_redis_keys
        @daemon_data.queue_redis_keys
      end

      def running?
        !!(@thread && @thread.alive?)
      end

      def start
        # ping to check that it can communicate with redis before running,
        # this is friendlier than starting and continously erroring because
        # it can't dequeue
        @client.ping
        @state.set :run
        @thread ||= Thread.new{ work_loop }
      end

      def stop(wait = false)
        return unless self.running?
        @state.set :stop
        wakeup_thread
        wait_for_shutdown if wait
      end

      def halt(wait = false)
        return unless self.running?
        @state.set :halt
        wakeup_thread
        wait_for_shutdown if wait
      end

      private

      def work_loop
        setup
        fetch_messages while @state.run?
      rescue StandardError => exception
        @state.set :stop
        log "Error occurred while running the daemon, exiting", :error
        log "#{exception.class}: #{exception.message}", :error
        (exception.backtrace || []).each{ |l| log(l, :error) }
      ensure
        teardown
      end

      def setup
       # clear any signals that are already on the signals list in redis
       @client.clear(self.signals_redis_key)
        @worker_pool.start
      end

      def fetch_messages
        if !@worker_pool.worker_available? && @state.run?
          @worker_available.wait
        end
        return unless @worker_pool.worker_available? && @state.run?

        # shuffle the queue redis keys to avoid queue starvation, redis will
        # pull messages off queues in the order they are passed to the command,
        # by shuffling we ensure they are randomly ordered so every queue
        # should  get a chance; use 0 for the brpop timeout which means block
        # indefinitely; rescue runtime errors so the daemon thread doesn't fail
        # if redis is temporarily down, sleep for a second to keep the thread
        # from thrashing by repeatedly erroring if redis is down
        begin
          args = [self.signals_redis_key, self.queue_redis_keys.shuffle, 0].flatten
          redis_key, encoded_payload = @client.block_dequeue(*args)
          if redis_key != @signals_redis_key
            @worker_pool.push(QueueItem.new(redis_key, encoded_payload))
          end
        rescue RuntimeError => exception
          log "Error occurred while dequeueing", :error
          log "#{exception.class}: #{exception.message}", :error
          (exception.backtrace || []).each{ |l| log(l, :error) }
          sleep 1
        end
      end

      def teardown
        timeout = @state.halt? ? 0 : self.daemon_data.shutdown_timeout
        @worker_pool.shutdown(timeout)

        log "Requeueing #{@worker_pool.work_items.size} message(s)"
        @worker_pool.work_items.each do |qi|
          @client.prepend(qi.queue_redis_key, qi.encoded_payload)
        end
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

      def config
        @config ||= Config.new
      end

      def name(value = nil)
        self.config.name = value if !value.nil?
        self.config.name
      end

      def pid_file(value = nil)
        self.config.pid_file = value if !value.nil?
        self.config.pid_file
      end

      def shutdown_timeout(value = nil)
        self.config.shutdown_timeout = value if !value.nil?
        self.config.shutdown_timeout
      end

      def worker_class(value = nil)
        self.config.worker_class = value if !value.nil?
        self.config.worker_class
      end

      def worker_params(value = nil)
        self.config.worker_params = value if !value.nil?
        self.config.worker_params
      end

      def num_workers(new_num_workers = nil)
        self.config.num_workers = new_num_workers if new_num_workers
        self.config.num_workers
      end
      alias :workers :num_workers

      def init(&block)
        self.config.init_procs << block
      end

      def error(&block)
        self.config.error_procs << block
      end

      def logger(value = nil)
        self.config.logger = value if !value.nil?
        self.config.logger
      end

      def queue(value)
        self.config.queues << value
      end

      def queues
        self.configuration.queues
      end

      # flags

      def verbose_logging(value = nil)
        self.config.verbose_logging = value if !value.nil?
        self.config.verbose_logging
      end

    end

    class Config

      DEFAULT_NUM_WORKERS = 4.freeze

      attr_accessor :name, :pid_file, :shutdown_timeout
      attr_accessor :worker_class, :worker_params, :num_workers
      attr_accessor :init_procs, :error_procs, :logger, :queues
      attr_accessor :verbose_logging

      def initialize
        @name             = nil
        @pid_file         = nil
        @shutdown_timeout = nil
        @worker_class     = DefaultWorker
        @worker_params    = nil
        @num_workers      = DEFAULT_NUM_WORKERS
        @init_procs       = []
        @error_procs      = []
        @logger           = Qs::NullLogger.new
        @queues           = []

        @verbose_logging = true

        @valid = nil
      end

      def routes
        @queues.map(&:routes).flatten
      end

      def valid?
        !!@valid
      end

      # for the config to be considered "valid", a few things need to happen.
      # The key here is that this only needs to be done _once_ for each config.

      def validate!
        return @valid if !@valid.nil? # only need to run this once per config

        # ensure all user and plugin configs/settings are applied
        self.init_procs.each(&:call)
        if self.queues.empty? || self.name.nil?
          raise InvalidError, "a name and at least 1 queue must be configured"
        end

        # validate the worker class
        if !self.worker_class.kind_of?(Class) || !self.worker_class.include?(Qs::Worker)
          raise InvalidError, "worker class must include `#{Qs::Worker}`"
        end

        # validate the routes
        self.routes.each(&:validate!)

        @valid = true # if it made it this far, it's valid!
      end

    end

    DefaultWorker = Class.new{ include Qs::Worker }
    InvalidError  = Class.new(ArgumentError)

    class WorkerAvailable
      def initialize
        @mutex    = Mutex.new
        @cond_var = ConditionVariable.new
      end

      def wait;   @mutex.synchronize{ @cond_var.wait(@mutex) }; end
      def signal; @mutex.synchronize{ @cond_var.signal };       end
    end

    class State < DatWorkerPool::LockedObject
      def run?;  self.value == :run;  end
      def stop?; self.value == :stop; end
      def halt?; self.value == :halt; end
    end

  end

end
