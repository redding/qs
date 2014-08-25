require 'assert'
require 'qs/cli'

require 'qs/tmp_daemon'

class Qs::CLI

  class UnitTests < Assert::Context
    desc "Qs::CLI"
    setup do
      @kernel_spy = KernelSpy.new
      @file_path = Factory.file_path

      @daemon = TestDaemon.new

      @config_file = FakeConfigFile.new(@daemon)
      Assert.stub(Qs::ConfigFile, :new).with(@file_path){ @config_file }

      @cli = Qs::CLI.new(@kernel_spy)
    end
    subject{ @cli }

    should have_cmeths :run
    should have_imeths :run

  end

  class CommandTests < UnitTests
    setup do
      @process_spy = ProcessSpy.new
      @process_signal_spy = ProcessSignalSpy.new
    end

  end

  class DefaultsTests < CommandTests
    desc "with no command or file path"
    setup do
      file_path = 'config.qs'
      Assert.stub(Qs::ConfigFile, :new).with(file_path){ @config_file }
      Assert.stub(Qs::Process, :new).with(@daemon, :daemonize => false) do
        @process_spy
      end

      @cli.run
    end

    should "have defaulted the command and file path" do
      assert_true @process_spy.run_called
    end

  end

  class RunTests < CommandTests
    desc "with the run command"
    setup do
      Assert.stub(Qs::Process, :new).with(@daemon, :daemonize => false) do
        @process_spy
      end

      @cli.run(@file_path, 'run')
    end

    should "have built and run a non-daemonized process" do
      assert_true @process_spy.run_called
    end

  end

  class StartTests < CommandTests
    desc "with the start command"
    setup do
      Assert.stub(Qs::Process, :new).with(@daemon, :daemonize => true) do
        @process_spy
      end

      @cli.run(@file_path, 'start')
    end

    should "have built and run a daemonized process" do
      assert_true @process_spy.run_called
    end

  end

  class StopTests < CommandTests
    desc "with the stop command"
    setup do
      Assert.stub(Qs::ProcessSignal, :new).with(@daemon, 'TERM') do
        @process_signal_spy
      end

      @cli.run(@file_path, 'stop')
    end

    should "have built and sent a TERM signal" do
      assert_true @process_signal_spy.send_called
    end

  end

  class RestartTests < CommandTests
    desc "with the restart command"
    setup do
      Assert.stub(Qs::ProcessSignal, :new).with(@daemon, 'USR2') do
        @process_signal_spy
      end

      @cli.run(@file_path, 'restart')
    end

    should "have built and sent a USR2 signal" do
      assert_true @process_signal_spy.send_called
    end

  end

  class InvalidCommandTests < UnitTests
    desc "with an invalid command"
    setup do
      @command = Factory.string
      @cli.run(@file_path, @command)
    end

    should "output the error with the help" do
      expected = "#{@command.inspect} is not a valid command"
      assert_includes expected, @kernel_spy.output
      assert_includes "Usage: qs", @kernel_spy.output
    end

  end

  class KernelSpy
    attr_reader :exit_status

    def initialize
      @output = StringIO.new
      @exit_status = nil
    end

    def output
      @output.rewind
      @output.read
    end

    def puts(message)
      @output.puts(message)
    end

    def exit(code)
      @exit_status = code
    end
  end

  class TestDaemon
    include Qs::TmpDaemon
  end

  FakeConfigFile = Struct.new(:daemon)

  class ProcessSpy
    attr_reader :run_called

    def initialize
      @run_called = false
    end

    def run
      @run_called = true
    end
  end

  class ProcessSignalSpy
    attr_reader :send_called

    def initialize
      @send_called = false
    end

    def send
      @send_called = true
    end
  end

end
