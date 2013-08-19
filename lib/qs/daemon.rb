require 'ns-options'
require 'ns-options/boolean'

require 'qs/queue'

module Qs; end
module Qs::Daemon

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

  def self.included(klass)
    klass.class_eval do
      extend ClassMethods
      include InstanceMethods
    end
  end

  module ClassMethods

    def configuration
      @configuration ||= Configuration.new
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

  module InstanceMethods

    attr_reader :configuration

    def initialize
      @configuration = Configuration.new(self.class.configuration.to_hash)
      @configuration.validate!

      # TODO - state and signal handling
      set_state :init
      @signal_queue ||= []
    end

    def pid_file
      @configuration.pid_file
    end

    # This is all temporary
    attr_accessor :queue_name, :logger, :redis_ip, :redis_port
    attr_accessor :thread, :state

    def run
      set_state :run
      @thread = Thread.new do
        loop do
          break if !@state.run?
          sleep 0.5
          handle_signal(@signal_queue.pop) unless @signal_queue.empty?
        end
      end
    end

    def join_thread
      @thread.join
    end

    def signal_stop
      @signal_queue << :stop
    end

    def signal_halt
      @signal_queue << :halt
    end

    def signal_restart
      @signal_queue << :restart
    end

    def running?
      @thread && @thread.alive?
    end

    def in_stop_state?
      @state.stop?
    end

    def in_halt_state?
      @state.halt?
    end

    def in_restart_state?
      @state.restart?
    end

    private

    def handle_signal(signal)
      set_state(signal)
    end

    def set_state(name)
      @state = State.new(name)
    end

  end

  # TODO - not sure what I want to do with the state handling yet
  class State
    def initialize(name)
      @name = name.to_sym
      # TODO - validation
    end

    def run?
      @name == :run
    end

    def restart?
      @name == :restart
    end

    def stop?
      @name == :stop
    end

    def halt?
      @name == :halt
    end
  end

end
