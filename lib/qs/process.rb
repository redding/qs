require 'qs/io_pipe'
require 'qs/pid_file'

module Qs

  class Process

    HALT    = 'H'.freeze
    STOP    = 'S'.freeze
    RESTART = 'R'.freeze

    attr_reader :daemon, :name
    attr_reader :pid_file, :signal_io, :restart_cmd

    def initialize(daemon, options = nil)
      options ||= {}
      @daemon = daemon
      process_label = ignore_if_blank(ENV['QS_PROCESS_LABEL']) || @daemon.name
      @name   = "qs: #{process_label}"
      @logger = @daemon.logger

      @pid_file    = PIDFile.new(@daemon.pid_file)
      @signal_io   = IOPipe.new
      @restart_cmd = RestartCmd.new

      skip_daemonize = ignore_if_blank(ENV['QS_SKIP_DAEMONIZE'])
      @daemonize = !!options[:daemonize] && !skip_daemonize
    end

    def run
      ::Process.daemon(true) if self.daemonize?
      log "Starting Qs daemon for #{@daemon.name}"

      $0 = @name
      @pid_file.write
      log "PID: #{@pid_file.pid}"

      @signal_io.setup
      trap_signals(@signal_io)

      start_daemon(@daemon)

      signal = catch(:signal) do
        wait_for_signals(@signal_io, @daemon)
      end
      @signal_io.teardown

      run_restart_cmd(@daemon, @restart_cmd) if signal == RESTART
    ensure
      @pid_file.remove
    end

    def daemonize?
      @daemonize
    end

    private

    def start_daemon(daemon)
      @daemon.start
      log "#{@daemon.name} daemon started and ready."
    rescue StandardError => exception
      log "#{@daemon.name} daemon never started."
      raise exception
    end

    def trap_signals(signal_io)
      trap_signal('INT'){  signal_io.write(HALT) }
      trap_signal('TERM'){ signal_io.write(STOP) }
      trap_signal('USR2'){ signal_io.write(RESTART) }
    end

    def trap_signal(signal, &block)
      ::Signal.trap(signal, &block)
    rescue ArgumentError
      log "'#{signal}' signal not supported"
    end

    def wait_for_signals(signal_io, daemon)
      while signal_io.wait do
        os_signal = signal_io.read
        handle_signal(os_signal, daemon)
      end
    end

    def handle_signal(signal, daemon)
      log "Got '#{signal}' signal"
      case signal
      when HALT
        daemon.halt(true)
      when STOP, RESTART
        daemon.stop(true)
      end
      throw :signal, signal
    end

    def run_restart_cmd(daemon, restart_cmd)
      log "Restarting #{daemon.name} daemon"
      ENV['QS_SKIP_DAEMONIZE'] = 'yes'
      restart_cmd.run
    end

    def log(message)
      @logger.info "[Qs] #{message}"
    end

    def ignore_if_blank(value, &block)
      block ||= proc{ |v| v }
      block.call(value) if value && !value.empty?
    end

  end

  class RestartCmd
    attr_reader :argv, :dir

    def initialize
      require 'rubygems'
      @dir  = get_pwd
      @argv = [Gem.ruby, $0, ARGV.dup].flatten
    end

    def run
      Dir.chdir self.dir
      Kernel.exec(*self.argv)
    end

    private

    # Trick from puma/unicorn. Favor PWD because it contains an unresolved
    # symlink. This is useful when restarting after deploying; the original
    # directory may be removed, but the symlink is pointing to a new
    # directory.
    def get_pwd
      return Dir.pwd if ENV['PWD'].nil?
      env_stat = File.stat(ENV['PWD'])
      pwd_stat = File.stat(Dir.pwd)
      if env_stat.ino == pwd_stat.ino && env_stat.dev == pwd_stat.dev
        ENV['PWD']
      else
        Dir.pwd
      end
    end
  end

  # This is from puma for 1.8 compatibility. Ruby 1.9+ defines a
  # `Process.daemon` for daemonizing processes. This defines the method when it
  # isn't provided, i.e. Ruby 1.8.
  unless ::Process.respond_to?(:daemon)
    ::Process.class_eval do

      # Full explanation: http://www.steve.org.uk/Reference/Unix/faq_2.html#SEC16
      def self.daemon(no_chdir = false, no_close = false)
        exit if fork
        ::Process.setsid
        exit if fork
        Dir.chdir '/' unless no_chdir
        if !no_close
          null = File.open('/dev/null', 'w')
          STDIN.reopen null
          STDOUT.reopen null
          STDERR.reopen null
        end
        return 0
      end

    end
  end

end
