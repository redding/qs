require 'assert'
require 'qs/cli'

require 'qs/daemon'
require 'qs/process'
require 'qs/version'

class Qs::CLI

  class UnitTests < Assert::Context
    desc "Qs::CLI"
    setup do
      @kernel_spy = KernelSpy.new
      @cli = Qs::CLI.new(@kernel_spy)
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
      assert_equal subject.help, @kernel_spy.output
      assert_equal 0, @kernel_spy.exit_status
    end

  end

  class RunVersionTests < UnitTests
    desc "with the --version switch"
    setup do
      @cli.run([ "--version" ])
    end

    should "print out the version and exit with a 0" do
      assert_equal Qs::VERSION, @kernel_spy.output
      assert_equal 0, @kernel_spy.exit_status
    end

  end

  class OnCLIErrorTests < UnitTests
    desc "when run raises a CLI error"
    setup do
      @exception = Qs::CLIRB::Error.new("something went wrong")
      @cli.stubs(:run!).raises(@exception)
      @cli.run
    end

    should "print out the exception message, the help and exit with a 1" do
      assert_includes @exception.message, @kernel_spy.output
      assert_includes subject.help, @kernel_spy.output
      assert_equal 1, @kernel_spy.exit_status
    end

  end

  class OnInvalidConfigErrorTests < UnitTests
    desc "when run raises an invalid config error"
    setup do
      @exception = Qs::Config::InvalidError.new("invalid config file")
      @cli.stubs(:run!).raises(@exception)
      @cli.run
    end

    should "print out the exception message, the help and exit with a 1" do
      assert_includes @exception.message, @kernel_spy.output
      assert_includes subject.help, @kernel_spy.output
      assert_equal 1, @kernel_spy.exit_status
    end

  end

    class OnInvalidProcessErrorTests < UnitTests
    desc "when run raises an invalid process error"
    setup do
      @exception = Qs::Process::InvalidError.new("invalid command")
      @cli.stubs(:run!).raises(@exception)
      @cli.run
    end

    should "print out the exception message, the help and exit with a 1" do
      assert_includes @exception.message, @kernel_spy.output
      assert_includes subject.help, @kernel_spy.output
      assert_equal 1, @kernel_spy.exit_status
    end

  end

  class AllOtherExceptionsTests < UnitTests
    desc "when run raises any other exception"
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
      expected = "#{@exception.class}: #{@exception.message}"
      assert_includes expected, @kernel_spy.output
      expected = @exception.backtrace.join("\n")
      assert_includes expected, @kernel_spy.output
      assert_equal 1, @kernel_spy.exit_status
    end

  end

  class KernelSpy
    attr_reader :output, :exit_status

    def initialize
      @output = ""
      @exit_status = nil
    end

    def puts(message)
      @output << message
    end

    def exit(status)
      @exit_status = status
    end
  end

end
