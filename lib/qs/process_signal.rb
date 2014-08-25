require 'qs/pid_file'

module Qs

  class ProcessSignal

    attr_reader :signal, :pid

    def initialize(daemon, signal)
      @signal = signal
      @pid = PIDFile.new(daemon.pid_file).pid
    end

    def send
      ::Process.kill(@signal, @pid)
    end

  end

end
