module Qs; end
module Qs::Daemon

  # This is all temporary
  attr_accessor :queue_name, :logger, :pid_file, :redis_ip, :redis_port
  attr_accessor :thread, :state

  def initialize
    set_state :init
    @signal_queue ||= []
  end

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
