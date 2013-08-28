require 'assert'
require 'qs/process'

require 'qs/daemon'
require 'qs/queue'
require 'logger'
require 'thread'
require 'test/support/spy'

class Qs::Process

  class UnitTests < Assert::Context
    desc "Qs::Process"
    setup do
      @daemon = ProcessTestsDaemon.new
      @process = Qs::Process.new(@daemon)
    end
    subject{ @process }

    should have_imeths :call
    should have_cmeths :call

    should "raise an unknown command error when " \
           "passing an unexpected command string to #call" do
      exception = nil
      begin; @process.call('invalid'); rescue Exception => exception; end
      assert_instance_of Qs::Process::InvalidError, exception
      assert_equal "Unknown command: \"invalid\"", exception.message
    end

  end

  class RunningADaemonTests < UnitTests
    setup do
      @signal_spy  = Spy.new(::Signal).tap{ |s| s.track(:trap) }
      @dir_spy     = Spy.new(::Dir).tap{ |s| s.track(:chdir) }
      @kernel_spy  = Spy.new(::Kernel).tap{ |s| s.track(:exec) }
      @handler_spy = Spy.new(Qs::Process::DaemonHandler).tap do |s|
        s.track_on_instance(:daemonize!)
      end
      @current_qs_skip_daemonize = ENV['QS_SKIP_DAEMONIZE']
      @current_process_name = $0
    end
    teardown do
      $0 = @current_process_name
      ENV['QS_SKIP_DAEMONIZE'] = @current_qs_skip_daemonize
      @handler_spy.ignore_on_instance(:daemonize!)
      @kernel_spy.ignore(:exec)
      @dir_spy.ignore(:chdir)
      @signal_spy.ignore(:trap)
    end

    private

    def call_in_thread(command)
      @process_thread = Thread.new do
        begin
          @process.call(command)
        rescue Exception => exception
          if ENV['DEBUG']
            puts exception.inspect
            puts exception.backtrace.join("\n")
          end
        end
      end
      @process_thread.abort_on_exception = false
      @process_thread.join(0.1)
      @process_thread
    end

    def shutdown_thread
      @daemon.stop(true)
      @process_thread.join if @process_thread
      @process_thread = nil
    end

  end

  class CallRunTests < RunningADaemonTests
    desc "calling the 'run' command"
    setup do
      call_in_thread('run')
    end
    teardown do
      shutdown_thread
    end

    should "set the process name" do
      assert_equal "qs_test__main", $0
    end

    should "have written the PID file" do
      assert File.exists?(@daemon.pid_file)
    end

    should "remove the PID file when it exits" do
      @daemon.stop(true)
      @process_thread.join
      assert_not File.exists?(@daemon.pid_file)
    end

    should "remove the PID file even when an exception occurs" do
      @process_thread.raise("something went wrong")
      @process_thread.join
      assert_not File.exists?(@daemon.pid_file)
    end

    should "run the daemon without daemonizing the process" do
      assert @daemon.running?
      assert_empty @handler_spy.instance_method(:daemonize!).calls
    end

    should "trap the TERM signal and stop the daemon when triggered" do
      trap_call = @signal_spy.method(:trap).calls[0]
      assert_equal "TERM", trap_call.args[0]

      trap_call.block.call
      @process_thread.join
      assert @daemon.stopped?
      assert_not @daemon.running?
    end

    should "trap the INT signal and halt the daemon when triggered" do
      trap_call = @signal_spy.method(:trap).calls[1]
      assert_equal "INT", trap_call.args[0]

      trap_call.block.call
      @process_thread.join
      assert @daemon.halted?
      assert_not @daemon.running?
    end

    should "trap the USR2 signal and restart the process when triggered" do
      trap_call = @signal_spy.method(:trap).calls[2]
      assert_equal "USR2", trap_call.args[0]

      trap_call.block.call
      @process_thread.join
      assert @daemon.stopped?
      assert_not @daemon.running?

      # should have restarted the current process
      chdir_call = @dir_spy.method(:chdir).calls[0]
      exec_call  = @kernel_spy.method(:exec).calls[0]
      assert_equal 'yes', ENV['QS_SKIP_DAEMONIZE']
      assert_equal ENV['PWD'], chdir_call.args[0]
      expected = [ Gem.ruby, @current_process_name, ARGV.dup ].flatten
      assert expected, exec_call.args[0]
    end

  end

  class CallStartTests < RunningADaemonTests
    desc "calling the 'start' command"
    setup do
      call_in_thread('start')
    end
    teardown do
      shutdown_thread
    end

    should "daemonize the process and run the daemon" do
      assert_not_empty @handler_spy.instance_method(:daemonize!).calls
      assert @daemon.running?
    end

  end

  class CallStartWithSkipDaemonizeTests < RunningADaemonTests
    desc "calling the 'start' command with QS_SKIP_DAEMONIZE set"
    setup do
      ENV['QS_SKIP_DAEMONIZE'] = 'yes'
      call_in_thread('start')
    end
    teardown do
      shutdown_thread
    end

    should "run the daemon without daemonizing the process" do
      assert @daemon.running?
      assert_empty @handler_spy.instance_method(:daemonize!).calls
    end

  end

  class RunThatCantWritePIDTests < RunningADaemonTests
    desc "running the daemon when it can't write the PID file"
    setup do
      File.stubs(:open).raises("cant open file")
    end
    teardown do
      File.unstub(:open)
    end

    should "raise an error about not being able to write the PID file" do
      exception = nil
      begin; @process.call('run'); rescue Exception => exception; end
      assert_instance_of Qs::Process::InvalidError, exception
      expected = "Can't write pid to file #{@daemon.pid_file.to_s.inspect}"
      assert_equal expected, exception.message
    end

  end

  class SendingASignalTests < UnitTests
    setup do
      File.open(@daemon.pid_file, 'w'){ |f| f.puts ::Process.pid }
      @process_spy = Spy.new(::Process).tap{ |s| s.track(:kill) }
    end
    teardown do
      FileUtils.rm_rf(@daemon.pid_file)
    end
  end

  class CallStopTests < SendingASignalTests
    desc "calling the 'stop' command"
    setup do
      @process.call('stop')
    end

    should "have sent a TERM signal to the daemon's PID" do
      kill_call = @process_spy.method(:kill).calls.first
      assert_equal "TERM",        kill_call.args[0]
      assert_equal ::Process.pid, kill_call.args[1]
    end

  end

  class CallRestartTests < SendingASignalTests
    desc "calling the 'restart' command"
    setup do
      @process.call('restart')
    end

    should "have sent a USR2 signal to the daemon's PID" do
      kill_call = @process_spy.method(:kill).calls.first
      assert_equal "USR2",        kill_call.args[0]
      assert_equal ::Process.pid, kill_call.args[1]
    end

  end

  class SendingASignalThatCantReadPIDTests < SendingASignalTests
    desc "sending a signal when it can't read the PID file"
    setup do
      File.stubs(:read).raises("cant open file")
    end
    teardown do
      File.unstub(:read)
    end

    should "raise an error about not being able to read the PID" do
      exception = nil
      begin; @process.call('stop'); rescue Exception => exception; end
      assert_instance_of Qs::Process::InvalidError, exception
      expected = "A PID couldn't be read from #{@daemon.pid_file.to_s.inspect}"
      assert_equal expected, exception.message
    end

  end

  # TODO - this is not a finalized method for creating queues
  ProcessTestsQueue = Qs::Queue.new.tap do |q|
    q.name   = "test__main"
    q.logger = Logger.new(File.open(ROOT.join("log/test.log"), 'w')).tap do |l|
      l.level = Logger::DEBUG
    end
  end

  class ProcessTestsDaemon
    include Qs::Daemon
    queue ProcessTestsQueue
    pid_file ROOT.join("tmp/test.pid")
    workers 1
    wait_timeout 0.5
  end

end
