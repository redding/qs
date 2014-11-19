require 'ns-options'
require 'pathname'
require 'qs/logger'

module Qs

  module Daemon

    def self.included(klass)
      klass.class_eval do
        extend ClassMethods
        include InstanceMethods
      end
    end

    module InstanceMethods

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

    InvalidError = Class.new(RuntimeError)

  end

end
