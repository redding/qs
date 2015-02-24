require 'qs/pid_file'

module Qs

  class Process

    attr_reader :daemon, :name, :pid_file, :restart_cmd

    def initialize(daemon, options = nil)
      options ||= {}
      @daemon = daemon
      @logger = @daemon.logger
      @pid_file = PIDFile.new(@daemon.pid_file)
      @restart_cmd = RestartCmd.new

      @name = ignore_if_blank(ENV['QS_PROCESS_NAME']) || "qs-#{@daemon.name}"

      @daemonize = !!options[:daemonize]
      @skip_daemonize = !!ignore_if_blank(ENV['QS_SKIP_DAEMONIZE'])
      @restart = false
    end

    def run
      ::Process.daemon(true) if self.daemonize?
      log "Starting Qs daemon for #{@daemon.name}..."

      $0 = @name
      @pid_file.write
      log "PID: #{@pid_file.pid}"

      ::Signal.trap("TERM"){ @daemon.stop }
      ::Signal.trap("INT"){ @daemon.halt }
      ::Signal.trap("USR2") do
        @daemon.stop
        @restart = true
      end

      thread = @daemon.start
      log "#{@daemon.name} daemon started and ready."
      thread.join
      run_restart_cmd if self.restart?
    rescue StandardError => exception
      log "Error: #{exception.message}"
      log "#{@daemon.name} daemon never started."
    ensure
      @pid_file.remove
    end

    def daemonize?
      @daemonize && !@skip_daemonize
    end

    def restart?
      @restart
    end

    private

    def log(message)
      @logger.info "[Qs] #{message}"
    end

    def run_restart_cmd
      log "Restarting #{@daemon.name} daemon..."
      ENV['QS_SKIP_DAEMONIZE'] = 'yes'
      @restart_cmd.run
    end

    def default_if_blank(value, default, &block)
      ignore_if_blank(value, &block) || default
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
