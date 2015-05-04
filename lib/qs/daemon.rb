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

    def self.included(klass)
      klass.class_eval do
        extend ClassMethods
        include InstanceMethods

        init{ Qs.init }

      end
    end

    module InstanceMethods

      attr_reader :daemon_data

      # * Set the size of the client to the max workers + 1. This ensures we
      #   have 1 connection for fetching work from redis and at least 1
      #   connection for each worker to requeue its job when hard-shutdown.
      def initialize
        self.class.configuration.validate!
        # build a limited daemon data OR merge with daemon
        @daemon_data = DaemonData.new(self.class.configuration.to_hash)

        @work_loop = WorkLoop.new(self)
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
        @work_loop.running?
      end

      def start
        @work_loop.start
      end

      def stop(*args)
        @work_loop.stop(*args)
      end

      def halt(*args)
        @work_loop.halt(*args)
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

      def valid?
        !!@valid
      end

      def validate!
        return @valid if !@valid.nil?
        self.init_procs.each(&:call)
        if self.queues.empty? || !self.required_set?
          raise InvalidError, "a name and queue must be configured"
        end
        self.queues.each(&:validate!)
        @valid = true
      end
    end

    InvalidError = Class.new(ArgumentError)

  end

end
