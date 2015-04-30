require 'assert'
require 'qs/process'

require 'qs/daemon'
require 'test/support/pid_file_spy'

class Qs::Process

  class UnitTests < Assert::Context
    desc "Qs::Process"
    setup do
      @process_class = Qs::Process
    end
    subject{ @process_class }

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @current_env_process_name   = ENV['QS_PROCESS_NAME']
      @current_env_skip_daemonize = ENV['QS_SKIP_DAEMONIZE']
      ENV.delete('QS_PROCESS_NAME')
      ENV.delete('QS_SKIP_DAEMONIZE')

      @daemon_spy = DaemonSpy.new

      @pid_file_spy = PIDFileSpy.new(Factory.integer)
      Assert.stub(Qs::PIDFile, :new).with(@daemon_spy.pid_file) do
        @pid_file_spy
      end

      @restart_cmd_spy = RestartCmdSpy.new
      Assert.stub(Qs::RestartCmd, :new){ @restart_cmd_spy }

      @process = @process_class.new(@daemon_spy)
    end
    teardown do
      ENV['QS_SKIP_DAEMONIZE'] = @current_env_skip_daemonize
      ENV['QS_PROCESS_NAME']   = @current_env_process_name
    end
    subject{ @process }

    should have_readers :daemon, :name
    should have_readers :pid_file, :signal_io, :restart_cmd
    should have_imeths :run, :daemonize?

    should "know its daemon" do
      assert_equal @daemon_spy, subject.daemon
    end

    should "know its name, pid file, signal io and restart cmd" do
      assert_equal "qs-#{@daemon_spy.name}", subject.name
      assert_equal @pid_file_spy, subject.pid_file
      assert_instance_of Qs::IOPipe, subject.signal_io
      assert_equal @restart_cmd_spy, subject.restart_cmd
    end

    should "set its name using env vars" do
      ENV['QS_PROCESS_NAME'] = Factory.string
      process = @process_class.new(@daemon_spy)
      assert_equal ENV['QS_PROCESS_NAME'], process.name
    end

    should "ignore blank env values for its name" do
      ENV['QS_PROCESS_NAME'] = ''
      process = @process_class.new(@daemon_spy)
      assert_equal "qs-#{@daemon_spy.name}", process.name
    end

    should "not daemonize by default" do
      process = @process_class.new(@daemon_spy)
      assert_false process.daemonize?
    end

    should "daemonize if turned on" do
      process = @process_class.new(@daemon_spy, :daemonize => true)
      assert_true process.daemonize?
    end

    should "not daemonize if skipped via the env var" do
      ENV['QS_SKIP_DAEMONIZE'] = 'yes'
      process = @process_class.new(@daemon_spy)
      assert_false process.daemonize?
      process = @process_class.new(@daemon_spy, :daemonize => true)
      assert_false process.daemonize?
    end

    should "ignore blank env values for skip daemonize" do
      ENV['QS_SKIP_DAEMONIZE'] = ''
      process = @process_class.new(@daemon_spy, :daemonize => true)
      assert_true process.daemonize?
    end

  end

  class RunSetupTests < InitTests
    setup do
      @daemonize_called = false
      Assert.stub(::Process, :daemon).with(true){ @daemonize_called = true }

      @current_process_name = $0

      @signal_traps = []
      Assert.stub(::Signal, :trap) do |signal, &block|
        @signal_traps << SignalTrap.new(signal, block)
      end
    end
    teardown do
      @process.signal_io.write('H')
      @thread.join if @thread
      $0 = @current_process_name
    end

  end

  class RunTests < RunSetupTests
    desc "and run"
    setup do
      @thread = Thread.new{ @process.run }
      @thread.join(0.1)
    end

    should "not daemonize the process" do
      assert_false @daemonize_called
    end

    should "set the process name" do
      assert_equal $0, subject.name
    end

    should "write its PID file" do
      assert_true @pid_file_spy.write_called
    end

    should "trap signals" do
      assert_equal 3, @signal_traps.size
      assert_equal ['INT', 'TERM', 'USR2'], @signal_traps.map(&:signal)
    end

    should "start the daemon" do
      assert_true @daemon_spy.start_called
    end

    should "sleep its thread waiting for signals" do
      assert_equal 'sleep', @thread.status
    end

    should "not run the restart cmd" do
      assert_false @restart_cmd_spy.run_called
    end

  end

  class SignalTrapsTests < RunSetupTests
    desc "signal traps"
    setup do
      # setup the io pipe so we can see whats written to it
      @process.signal_io.setup
    end
    teardown do
      @process.signal_io.teardown
    end

    should "write the signals to processes signal IO" do
      @signal_traps.each do |signal_trap|
        signal_trap.block.call
        assert_equal signal_trap.signal, subject.signal_io.read
      end
    end

  end

  class RunWithDaemonizeTests < RunSetupTests
    desc "and run when it should daemonize"
    setup do
      Assert.stub(@process, :daemonize?){ true }
      @thread = Thread.new{ @process.run }
      @thread.join(0.1)
    end

    should "daemonize the process" do
      assert_true @daemonize_called
    end

  end

  class RunAndHaltTests < RunSetupTests
    desc "and run with a halt signal"
    setup do
      @thread = Thread.new{ @process.run }
      @process.signal_io.write('H') # send halt signal
      @thread.join(0.1)
    end

    should "halt its daemon" do
      assert_true @daemon_spy.halt_called
      assert_equal [true], @daemon_spy.halt_args
    end

    should "not set the env var to skip daemonize" do
      assert_equal @current_env_skip_daemonize, ENV['QS_SKIP_DAEMONIZE']
    end

    should "not run the restart cmd" do
      assert_false @restart_cmd_spy.run_called
    end

    should "remove the PID file" do
      assert_true @pid_file_spy.remove_called
    end

  end

  class RunAndStopTests < RunSetupTests
    desc "and run with a stop signal"
    setup do
      @thread = Thread.new{ @process.run }
      @process.signal_io.write('S') # send stop signal
      @thread.join(0.1)
    end

    should "stop its daemon" do
      assert_true @daemon_spy.stop_called
      assert_equal [true], @daemon_spy.stop_args
    end

    should "not set the env var to skip daemonize" do
      assert_equal @current_env_skip_daemonize, ENV['QS_SKIP_DAEMONIZE']
    end

    should "not run the restart cmd" do
      assert_false @restart_cmd_spy.run_called
    end

    should "remove the PID file" do
      assert_true @pid_file_spy.remove_called
    end

  end

  class RunAndRestartTests < RunSetupTests
    desc "and run with a restart signal"
    setup do
      @thread = Thread.new{ @process.run }
      @process.signal_io.write('R') # send restart signal
      @thread.join(0.1)
    end

    should "stop its daemon" do
      assert_true @daemon_spy.stop_called
      assert_equal [true], @daemon_spy.stop_args
    end

    should "set the env var to skip daemonize" do
      assert_equal 'yes', ENV['QS_SKIP_DAEMONIZE']
    end

    should "run the restart cmd" do
      assert_true @restart_cmd_spy.run_called
    end

  end

  class RunWithInvalidSignalTests < RunSetupTests
    desc "and run with unsupported signals"
    setup do
      # ruby throws an argument error if the OS doesn't support a signal
      Assert.stub(::Signal, :trap){ raise ArgumentError }

      @thread = Thread.new{ @process.run }
      @thread.join(0.1)
    end

    should "start normally" do
      assert_true @daemon_spy.start_called
      assert_equal 'sleep', @thread.status
    end

  end

  class RestartCmdTests < UnitTests
    desc "RestartCmd"
    setup do
      @current_pwd = ENV['PWD']
      ENV['PWD'] = Factory.path

      @ruby_pwd_stat = File.stat(Dir.pwd)
      env_pwd_stat = File.stat('/dev/null')
      Assert.stub(File, :stat).with(Dir.pwd){ @ruby_pwd_stat }
      Assert.stub(File, :stat).with(ENV['PWD']){ env_pwd_stat }

      @chdir_called_with = nil
      Assert.stub(Dir, :chdir){ |*args| @chdir_called_with = args }

      @exec_called_with = false
      Assert.stub(Kernel, :exec){ |*args| @exec_called_with = args }

      @cmd_class = Qs::RestartCmd
    end
    teardown do
      ENV['PWD'] = @current_pwd
    end
    subject{ @restart_cmd }

  end

  class RestartCmdInitTests < RestartCmdTests
    desc "when init"
    setup do
      @restart_cmd = @cmd_class.new
    end

    should have_readers :argv, :dir
    should have_imeths :run

    should "know its argv" do
      assert_equal [Gem.ruby, $0, ARGV].flatten, subject.argv
    end

    should "change the dir and run a kernel exec when run" do
      subject.run
      assert_equal [subject.dir], @chdir_called_with
      assert_equal subject.argv,  @exec_called_with
    end

  end

  class RestartCmdWithPWDEnvNoMatchTests < RestartCmdTests
    desc "when init with a PWD env variable that's not the ruby working dir"
    setup do
      @restart_cmd = @cmd_class.new
    end

    should "know its dir" do
      assert_equal Dir.pwd, subject.dir
    end

  end

  class RestartCmdWithPWDEnvInitTests < RestartCmdTests
    desc "when init with a PWD env variable that's the ruby working dir"
    setup do
      # make ENV['PWD'] point to the same file as Dir.pwd
      Assert.stub(File, :stat).with(ENV['PWD']){ @ruby_pwd_stat }
      @restart_cmd = @cmd_class.new
    end

    should "know its dir" do
      assert_equal ENV['PWD'], subject.dir
    end

  end

  class RestartCmdWithNoPWDEnvInitTests < RestartCmdTests
    desc "when init with a PWD env variable set"
    setup do
      ENV.delete('PWD')
      @restart_cmd = @cmd_class.new
    end

    should "know its dir" do
      assert_equal Dir.pwd, subject.dir
    end

  end

  SignalTrap = Struct.new(:signal, :block)

  class DaemonSpy
    include Qs::Daemon

    name Factory.string
    pid_file Factory.file_path

    queue Qs::Queue.new{ name Factory.string }

    attr_accessor :start_called, :stop_called, :halt_called
    attr_reader :start_args, :stop_args, :halt_args

    def initialize(*args)
      super
      @start_args   = nil
      @start_called = false
      @stop_args    = nil
      @stop_called  = false
      @halt_args    = nil
      @halt_called  = false
    end

    def start(*args)
      @start_args   = args
      @start_called = true
    end

    def stop(*args)
      @stop_args   = args
      @stop_called = true
    end

    def halt(*args)
      @halt_args   = args
      @halt_called = true
    end
  end

  class RestartCmdSpy
    attr_reader :run_called

    def initialize
      @run_called = false
    end

    def run
      @run_called = true
    end
  end

end
