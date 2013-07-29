require 'fileutils'

module Qs

  class Process

    InvalidError = Class.new(StandardError)

    def self.call(command, daemon)
      self.new(daemon).call(command)
    end

    def initialize(daemon)
      @daemon = daemon
    end

    def call(command)
      case command.to_sym
      when :run
        DaemonHandler.run(@daemon, false)
      when :start
        DaemonHandler.run(@daemon, true)
      when :stop
        Signal.send("TERM", @daemon)
      when :restart
        Signal.send("USR2", @daemon)
      else
        raise InvalidError, "Unknown command: #{command.inspect}"
      end
    end

    class DaemonHandler
      def self.run(daemon, daemonize_process)
        self.new(daemon).run(daemonize_process)
      end

      def initialize(daemon)
        @daemon       = daemon
        @queue_name   = @daemon.queue_name
        @logger       = @daemon.logger
        @process_name = ProcessName.new(@daemon)
        @pid_file     = PIDFile.new(@daemon.pid_file)
        @restart_cmd  = RestartCmd.new
      end

      def run(daemonize = false)
        daemonize!(true) if daemonize && !ENV['QS_SKIP_DAEMONIZE']
        log "Starting Qs daemon for #{@queue_name}..."
        $0 = @process_name
        @pid_file.write
        log "PID: #{::Process.pid}"

        ::Signal.trap("TERM"){ @daemon.signal_stop }
        ::Signal.trap("INT"){  @daemon.signal_halt }
        ::Signal.trap("USR2"){ @daemon.signal_restart }

        @daemon.run
        log "#{@queue_name} daemon started and ready."
        @daemon.join_thread
        restart if @daemon.in_restart_state?
      rescue RuntimeError => exception
        log "Error: #{exception.message}"
        log "#{@queue_name} daemon never started."
      ensure
        @pid_file.remove
      end

      private

      def log(message)
        @logger.info "[Qs] #{message}"
      end

      def restart
        log "Restarting #{@queue_name} daemon..."
        ENV['QS_SKIP_DAEMONIZE'] = 'yes'
        Dir.chdir @restart_cmd.dir
        Kernel.exec(*@restart_cmd.argv)
      end

      # Full explanation: http://www.steve.org.uk/Reference/Unix/faq_2.html#SEC16
      def daemonize!(no_chdir = false, no_close = false)
        exit if fork
        Process.setsid
        exit if fork
        Dir.chdir "/" unless no_chdir
        if !no_close
          null = File.open "/dev/null", 'w'
          STDIN.reopen null
          STDOUT.reopen null
          STDERR.reopen null
        end
        return 0
      end
    end

    class Signal
      def self.send(signal, daemon)
        self.new(signal, daemon).send
      end

      def initialize(signal, daemon)
        @signal   = signal
        @daemon   = daemon
        @pid_file = PIDFile.new(@daemon.pid_file)
      end

      def send
        ::Process.kill(@signal, @pid_file.pid)
      end
    end

    class PIDFile
      attr_reader :path

      def initialize(path)
        @path = (path || '/dev/null').to_s
      end

      def pid
        pid = File.read(@path).strip
        pid && !pid.empty? ? pid.to_i : raise('no pid in file')
      rescue Exception => exception
        error = InvalidError.new("A PID couldn't be read from #{@path.inspect}")
        error.set_backtrace(exception.backtrace)
        raise error
      end

      def write
        begin
          FileUtils.mkdir_p(File.dirname(@path))
          File.open(@path, 'w'){ |f| f.puts ::Process.pid }
        rescue Exception => exception
          error = InvalidError.new("Can't write pid to file #{@path.inspect}")
          error.set_backtrace(exception.backtrace)
          raise error
        end
      end

      def remove
        FileUtils.rm_f(@path)
      end

      def to_s
        @path
      end
    end

    class ProcessName < String
      def initialize(daemon)
        super "qs_#{daemon.queue_name}_#{daemon.redis_ip}_#{daemon.redis_port}"
      end
    end

    class RestartCmd
      attr_reader :argv, :dir

      def initialize
        require 'rubygems'
        @dir  = get_pwd
        @argv = [ Gem.ruby, $0, ARGV.dup ].flatten
      end

      protected

      # Trick from puma/unicorn. Favor PWD because it contains an unresolved
      # symlink. This is useful when restarting after deploying; the original
      # directory may be removed, but the symlink is pointing to a new
      # directory.
      def get_pwd
        env_stat = File.stat(ENV['PWD'])
        pwd_stat = File.stat(Dir.pwd)
        if env_stat.ino == pwd_stat.ino && env_stat.dev == pwd_stat.dev
          ENV['PWD']
        else
          Dir.pwd
        end
      end
    end

  end

end
