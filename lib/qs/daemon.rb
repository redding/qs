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

  module InstanceMethods

    attr_reader :queue_name, :pid_file, :logger
    attr_writer :check_for_signals_proc

    def initialize
      self.class.configuration.tap do |c|
        c.validate!
        @pid_file     = c.pid_file
        @wait_timeout = c.wait_timeout
        @queue        = c.queue
      end
      @queue_name = @queue.name
      @logger     = @queue.logger
      @check_for_signals_proc = proc{ }

      @work_loop_thread = nil
      set_state :stop
    end

    def start
      set_state :run
      @work_loop_thread ||= Thread.new{ work_loop }
    end

    def stop(wait = false)
      set_state :stop
      wait_for_shutdown if wait
    end

    def halt(wait = false)
      set_state :halt
      wait_for_shutdown if wait
    end

    def running?
      @work_loop_thread && @work_loop_thread.alive?
    end

    def stopped?
      @state.stop?
    end

    def halted?
      @state.halt?
    end

    private

    def work_loop
      @logger.debug "Starting work loop..."
      # TODO this is not complete
      while @state.run?
        check_for_signals
        sleep @wait_timeout # TODO this is temporary
      end
      @logger.debug "Stopping work loop..."
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

    def clear_thread
      @work_loop_thread = nil
    end

    def wait_for_shutdown
      @work_loop_thread.join if @work_loop_thread
    end

    def set_state(name)
      @state = State.new(name)
    end

  end

  class State
    def initialize(value)
      @symbol = value.to_sym
    end

    [ :run, :stop, :halt ].each do |name|
      define_method("#{name}?"){ @symbol == name }
    end
  end

end
