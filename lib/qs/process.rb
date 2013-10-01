require 'fileutils'

module Qs

  class Process

    InvalidError = Class.new(StandardError)

    def self.call(command, daemon)
      self.new(daemon).call(command)
    end

    def initialize(daemon)
      @daemon   = daemon
      @pid_file = PIDFile.new(@daemon.pid_file)
    end

    def call(command)
      case command.to_sym
      when :run
        DaemonHandler.run(@daemon, @pid_file, false)
      when :start
        DaemonHandler.run(@daemon, @pid_file, true)
      when :stop
        Signal.send("TERM", @pid_file.pid)
      when :restart
        Signal.send("USR2", @pid_file.pid)
      else
        raise InvalidError, "Unknown command: #{command.inspect}"
      end
    end

    class DaemonHandler
      def self.run(daemon, pid_file, daemonize_process)
        self.new(daemon, pid_file).run(daemonize_process)
      end

      def initialize(daemon, pid_file)
        @daemon       = daemon
        @queue_name   = @daemon.queue_name
        @logger       = @daemon.logger
        @pid_file     = pid_file
        @process_name = ProcessName.new(@queue_name)
        @restart_cmd  = RestartCmd.new
        @signal = nil
        @signal_queue = []
      end

      def run(daemonize = false)
        daemonize!(true) if daemonize && !ENV['QS_SKIP_DAEMONIZE']
        log "Starting Qs daemon for #{@queue_name}..."
        $0 = @process_name
        @pid_file.write
        log "PID: #{::Process.pid}"

        @daemon.check_for_signals_proc = proc{ check_signal_queue }
        ::Signal.trap("TERM"){ @signal_queue << :stop }
        ::Signal.trap("INT"){  @signal_queue << :halt }
        ::Signal.trap("USR2"){ @signal_queue << :restart }

        thread = @daemon.start
        log "#{@queue_name} daemon started and ready."
        thread.join
        restart if @signal == :restart
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

      def check_signal_queue
        @signal = @signal_queue.pop
        case @signal
        when :stop, :restart
          @daemon.stop
        when :halt
          @daemon.halt
        end
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
      def self.send(signal, pid)
        self.new(signal).send_to(pid)
      end

      def initialize(signal)
        @signal = signal
      end

      def send_to(pid)
        ::Process.kill(@signal, pid)
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
      def initialize(queue_name)
        super "qs_#{queue_name}"
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
