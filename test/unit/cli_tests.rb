require 'assert'
require 'qs/cli'

require 'qs/daemon'
require 'qs/process'
require 'test/support/spy'

class Qs::CLI

  class UnitTests < Assert::Context
    desc "Qs::CLI"
    setup do
      @cli = Qs::CLI.new

      @cli_spy = Spy.new(@cli).tap do |s|
        s.track(:puts)
        s.track(:exit)
      end
    end
    subject{ @cli }

    should have_imeths :run, :help
    should have_cmeths :run

    should "return a help message with #help" do
      expected = "Usage: qs <config file> <command> <options> \n" \
                 "Commands: run, start, stop, restart \n\n" \
                 "        --version\n" \
                 "        --help\n"
      assert_equal expected, subject.help
    end

  end

  class RunHelpTests < UnitTests
    desc "with the --help switch"
    setup do
      @cli.run([ "--help" ])
    end

    should "print out the help output and exit with a 0" do
      puts_call = @cli_spy.method(:puts).calls.first
      exit_call = @cli_spy.method(:exit).calls.first
      assert_equal subject.help, puts_call.args[0]
      assert_equal 0, exit_call.args[0]
    end

  end

  class RunVersionTests < UnitTests
    desc "with the --version switch"
    setup do
      @cli.run([ "--version" ])
    end

    should "print out the version and exit with a 0" do
      puts_call = @cli_spy.method(:puts).calls.first
      exit_call = @cli_spy.method(:exit).calls.first
      assert_equal Qs::VERSION, puts_call.args[0]
      assert_equal 0, exit_call.args[0]
    end

  end

  class OnCLIErrorTests < UnitTests
    desc "on a CLI error"
    setup do
      @exception = Qs::CLIRB::Error.new("no config file")
      @cli.stubs(:run!).raises(@exception)
      @cli.run
    end

    should "print out the exception message, the help and exit with a 1" do
      error_puts_call = @cli_spy.method(:puts).calls[0]
      help_puts_call  = @cli_spy.method(:puts).calls[1]
      exit_call = @cli_spy.method(:exit).calls.first
      assert_equal "#{@exception.message}\n\n", error_puts_call.args[0]
      assert_equal subject.help, help_puts_call.args[0]
      assert_equal 1, exit_call.args[0]
    end

  end

  class OnInvalidConfigErrorTests < UnitTests
    desc "on an invalid config error"
    setup do
      @exception = Qs::Config::InvalidError.new("invalid config file")
      @cli.stubs(:run!).raises(@exception)
      @cli.run
    end

    should "print out the exception message, the help and exit with a 1" do
      error_puts_call = @cli_spy.method(:puts).calls[0]
      help_puts_call  = @cli_spy.method(:puts).calls[1]
      exit_call = @cli_spy.method(:exit).calls.first
      assert_equal "#{@exception.message}\n\n", error_puts_call.args[0]
      assert_equal subject.help, help_puts_call.args[0]
      assert_equal 1, exit_call.args[0]
    end

  end

    class OnInvalidProcessErrorTests < UnitTests
    desc "on an invalid process error"
    setup do
      @exception = Qs::Process::InvalidError.new("invalid command")
      @cli.stubs(:run!).raises(@exception)
      @cli.run
    end

    should "print out the exception message, the help and exit with a 1" do
      error_puts_call = @cli_spy.method(:puts).calls[0]
      help_puts_call  = @cli_spy.method(:puts).calls[1]
      exit_call = @cli_spy.method(:exit).calls.first
      assert_equal "#{@exception.message}\n\n", error_puts_call.args[0]
      assert_equal subject.help, help_puts_call.args[0]
      assert_equal 1, exit_call.args[0]
    end

  end

  class AllOtherExceptionsTests < UnitTests
    desc "when other uncaught exceptions occur"
    setup do
      @current_debug = ENV['DEBUG']
      ENV['DEBUG'] = 'yes'
      @exception = StandardError.new("something went wrong")
      @cli.stubs(:run!).raises(@exception)
      @cli.run
    end
    teardown do
      ENV['DEBUG'] = @current_debug
    end

    should "print out the exception message, backtrace and exit with a 1" do
      error_puts_call     = @cli_spy.method(:puts).calls[0]
      backtrace_puts_call = @cli_spy.method(:puts).calls[1]
      exit_call = @cli_spy.method(:exit).calls.first

      expected = "#{@exception.class}: #{@exception.message}"
      assert_equal expected, error_puts_call.args[0]
      expected = @exception.backtrace.join("\n")
      assert_equal expected, backtrace_puts_call.args[0]
      assert_equal 1, exit_call.args[0]
    end

  end

end
