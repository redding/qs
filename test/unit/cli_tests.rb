require 'assert'
require 'qs/cli'

class Qs::CLI

  class BaseTests < Assert::Context
    desc "Qs::CLI"
    setup_once do
      Qs::CLI.class_eval{ include Spy }
    end
    setup do
      @cli = Qs::CLI.new
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

  class RunHelpTests < BaseTests
    desc "with the --help switch"
    setup do
      @cli.run([ "--help" ])
    end

    should "print out the help output and exit with a 0" do
      assert_equal subject.help, subject.puts_messages[0]
      assert_equal 0, subject.exit_status_code
    end

  end

  class RunVersionTests < BaseTests
    desc "with the --version switch"
    setup do
      @cli.run([ "--version" ])
    end

    should "print out the version and exit with a 0" do
      assert_equal Qs::VERSION, subject.puts_messages[0]
      assert_equal 0, subject.exit_status_code
    end

  end

  class OnCLIErrorTests < BaseTests
    desc "on a CLI error"
    setup do
      @exception = Qs::CLIRB::Error.new("no config file")
      @cli.stubs(:run!).raises(@exception)
      @cli.run
    end

    should "print out the exception message, the help and exit with a 1" do
      assert_equal "#{@exception.message}\n\n", subject.puts_messages[0]
      assert_equal subject.help, subject.puts_messages[1]
      assert_equal 1, subject.exit_status_code
    end

  end

  class AllOtherExceptionsTests < BaseTests
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
      expected = "#{@exception.class}: #{@exception.message}"
      assert_equal expected, subject.puts_messages[0]
      expected = @exception.backtrace.join("\n")
      assert_equal expected, subject.puts_messages[1]
      assert_equal 1, subject.exit_status_code
    end

  end

  module Spy

    attr_reader :exit_status_code, :puts_messages

    def puts(message)
      @puts_messages ||= []
      @puts_messages << message
    end

    def exit(status_code)
      @exit_status_code ||= status_code
    end

  end

end
