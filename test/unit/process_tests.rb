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
      @current_env_process_name = ENV['QS_PROCESS_NAME']
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
      ENV['QS_PROCESS_NAME'] = @current_env_process_name
    end
    subject{ @process }

    should have_readers :daemon, :name, :pid_file, :restart_cmd
    should have_imeths :run, :daemonize?, :restart?

    should "know its daemon" do
      assert_equal @daemon_spy, subject.daemon
    end

    should "know its name, pid file and restart cmd" do
      assert_equal "qs-#{@daemon_spy.name}", subject.name
      assert_equal @pid_file_spy, subject.pid_file
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

    should "not restart by default" do
      assert_false subject.restart?
    end

  end

  class RunSetupTests < InitTests
    setup do
      @daemonize_called = false
      Assert.stub(::Process, :daemon).with(true){ @daemonize_called = true }

      @current_process_name = $0

      @term_signal_trap_block = nil
      @term_signal_trap_called = false
      Assert.stub(::Signal, :trap).with("TERM") do |&block|
        @term_signal_trap_block = block
        @term_signal_trap_called = true
      end

      @int_signal_trap_block = nil
      @int_signal_trap_called = false
      Assert.stub(::Signal, :trap).with("INT") do |&block|
        @int_signal_trap_block = block
        @int_signal_trap_called = true
      end

      @usr2_signal_trap_block = nil
      @usr2_signal_trap_called = false
      Assert.stub(::Signal, :trap).with("USR2") do |&block|
        @usr2_signal_trap_block = block
        @usr2_signal_trap_called = true
      end
    end
    teardown do
      $0 = @current_process_name
    end

  end

  class RunTests < RunSetupTests
    desc "and run"
    setup do
      @process.run
    end

    should "not have daemonized the process" do
      assert_false @daemonize_called
    end

    should "have set the process name" do
      assert_equal $0, subject.name
    end

    should "have written the PID file" do
      assert_true @pid_file_spy.write_called
    end

    should "have trapped signals" do
      assert_true @term_signal_trap_called
      assert_false @daemon_spy.stop_called
      @term_signal_trap_block.call
      assert_true @daemon_spy.stop_called

      assert_true @int_signal_trap_called
      assert_false @daemon_spy.halt_called
      @int_signal_trap_block.call
      assert_true @daemon_spy.halt_called

      @daemon_spy.stop_called = false

      assert_true @usr2_signal_trap_called
      assert_false subject.restart?
      @usr2_signal_trap_block.call
      assert_true @daemon_spy.stop_called
      assert_true subject.restart?
    end

    should "have started the daemon" do
      assert_true @daemon_spy.start_called
    end

    should "have joined the daemon thread" do
      assert_true @daemon_spy.thread.join_called
    end

    should "not run the restart cmd" do
      assert_false @restart_cmd_spy.run_called
    end

    should "have removed the PID file" do
      assert_true @pid_file_spy.remove_called
    end

  end

  class RunWithDaemonizeTests < RunSetupTests
    desc "that should daemonize is run"
    setup do
      Assert.stub(@process, :daemonize?){ true }
      @process.run
    end

    should "have daemonized the process" do
      assert_true @daemonize_called
    end

  end

  class RunAndDaemonPausedTests < RunSetupTests
    desc "then run and sent a restart signal"
    setup do
      # mimicing pause being called by a signal, after the thread is joined
      @daemon_spy.thread.on_join{ @usr2_signal_trap_block.call }
      @process.run
    end

    should "set env vars for restarting and run the restart cmd" do
      assert_equal 'yes', ENV['QS_SKIP_DAEMONIZE']
      assert_true @restart_cmd_spy.run_called
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
    desc "when init with a PWD env variable that doesn't point to ruby working dir"
    setup do
      @restart_cmd = @cmd_class.new
    end

    should "know its dir" do
      assert_equal Dir.pwd, subject.dir
    end

  end

  class RestartCmdWithPWDEnvInitTests < RestartCmdTests
    desc "when init with a PWD env variable that points to the ruby working dir"
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

  class DaemonSpy
    include Qs::Daemon

    name Factory.string
    pid_file Factory.file_path

    queue Qs::Queue.new{ name Factory.string }

    attr_accessor :start_called, :stop_called, :halt_called
    attr_reader :start_args
    attr_reader :thread

    def initialize(*args)
      super
      @start_called = false
      @stop_called = false
      @halt_called = false

      @start_args = nil

      @thread = ThreadSpy.new
    end

    def start(*args)
      @start_args = args
      @start_called = true
      @thread
    end

    def stop(*args)
      @stop_called = true
    end

    def halt(*args)
      @halt_called = true
    end
  end

  class ThreadSpy
    attr_reader :join_called, :on_join_proc

    def initialize
      @join_called = false
      @on_join_proc = proc{ }
    end

    def on_join(&block)
      @on_join_proc = block
    end

    def join
      @join_called = true
      @on_join_proc.call
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
