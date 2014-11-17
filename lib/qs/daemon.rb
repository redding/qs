require 'dat-worker-pool'
require 'ns-options'
require 'ns-options/boolean'
require 'thread'

require 'qs/queue'
# require 'qs/worker'

module Qs

  module Daemon

    def self.included(klass)
      klass.class_eval do
        extend ClassMethods
        include InstanceMethods
      end
    end

    module InstanceMethods

      attr_reader :queue_name, :pid_file, :logger
      attr_writer :check_for_signals_proc

      def initialize
        self.class.configuration.tap do |c|
          c.validate!
          @pid_file         = c.pid_file
          @min_workers      = c.min_workers
          @max_workers      = c.max_workers
          @wait_timeout     = c.wait_timeout
          @shutdown_timeout = c.shutdown_timeout
          @error_procs      = c.error_procs
          @queue            = c.queue
        end
        @queue_name = @queue.name
        @logger     = @queue.logger
        @check_for_signals_proc = proc{ }

        @work_loop_thread = nil
        @worker_pool      = nil
        @signal = Signal.new(:stop)
      end

      def start
        @signal.set :start
        @work_loop_thread ||= Thread.new{ work_loop }
      end

      def stop(wait = false)
        @signal.set :stop
        wait_for_shutdown if wait
      end

      def halt(wait = false)
        @signal.set :halt
        wait_for_shutdown if wait
      end

      def running?
        @work_loop_thread && @work_loop_thread.alive?
      end

      private

      def process(job)
        Qs::Worker.new(@queue, @error_procs).run(job)
      end

      def work_loop
        @logger.debug "Starting work loop..."
        @worker_pool = DatWorkerPool.new(@min_workers, @max_workers) do |encoded_job|
          process(encoded_job)
        end
        while @signal.start?
          @worker_pool.add_work fetch_job
          check_for_signals
        end
        @logger.debug "Stopping work loop..."
        shutdown_worker_pool unless @signal.halt?
      rescue Exception => exception
        @logger.error "Exception occurred, stopping server!"
        @logger.error "#{exception.class}: #{exception.message}"
        @logger.error exception.backtrace.join("\n")
      ensure
        clear_thread
        @logger.debug "Stopped work loop"
      end

      def check_for_signals
        @check_for_signals_proc.call(self)
      end

      def fetch_job
        if @worker_pool.worker_available? && @worker_pool.queue_empty?
          @queue.fetch_job(@wait_timeout)
        else
          sleep(@wait_timeout); nil
        end
      end

      def shutdown_worker_pool
        # TODO - tweak, run every job off the worker-pool's queue (in-memory)
        # SystemTimer.timeout(@shutdown_timeout) do
        #   sleep(@wait_timeout) while !@worker_pool.queue_empty?
        # end
        # @worker_pool.shutdown(0)
        @logger.debug "Shutting down worker pool, letting it finish..."
        @worker_pool.shutdown(@shutdown_timeout)
        @worker_pool = nil
      end

      def clear_thread
        @work_loop_thread = nil
      end

      def wait_for_shutdown
        @work_loop_thread.join if @work_loop_thread
      end

    end

    module ClassMethods

      def configuration
        @configuration ||= Configuration.new
      end

      def queue(new_queue = nil)
        self.configuration.queue = new_queue if new_queue
        self.configuration.queue
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

      def wait_timeout(*args)
        self.configuration.wait_timeout(*args)
      end

      def shutdown_timeout(*args)
        self.configuration.shutdown_timeout(*args)
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

    class Configuration
      include NsOptions::Proxy

      option :pid_file, String, :default => 'qs.pid'

      option :min_workers, Integer, :default => 4
      option :max_workers, Integer, :default => 4

      option :wait_timeout,     Integer, :default => 5
      option :shutdown_timeout, Integer, :default => nil

      attr_accessor :error_procs, :init_procs, :queue

      def initialize(values = nil)
        self.apply(values || {})
        @error_procs, @init_procs = [], []
        @queue = Qs::Queue.new
        @valid = nil
      end

      def valid?
        !!@valid
      end

      # for the config to be considered "valid", a few things need to happen.  The
      # key here is that this only needs to be done _once_ for each config.

      def validate!
        return @valid if !@valid.nil?  # only need to run this once per config

        # ensure all user and plugin configs/settings are applied
        self.init_procs.each{ |p| p.call }

        # validate the jobs / event mappings
        self.mappings.each(&:validate!)

        @valid = true  # if it made it this far, its valid!
      end

      def mappings
        self.queue.mappings
      end
    end

  end

end
