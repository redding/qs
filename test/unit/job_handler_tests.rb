require 'assert'
require 'qs/job'
require 'qs/job_handler'
require 'qs/test_helpers'

module Qs::JobHandler

  class BaseTests < Assert::Context
    include Qs::TestHelpers

    desc "Qs::JobHandler"
    setup do
      @handler_class = MyTestApp::JobHandlers::TestJob
      @handler_args  = {'something' => 'awesome'}
      @handler = job_test_runner(@handler_class, @handler_args).handler
    end
    subject{ @handler }

    should have_readers :name, :args, :enqueued_job
    should have_imeths  :run, :run!, :init, :init!
    should have_imeths  :before_init, :after_init, :before_run, :after_run, :on_failure
    should have_imeths  :timeout, :logger

    should "know its default timeout" do
      assert_equal Qs.config.timeout, subject.timeout
    end

    should "know its name" do
      assert_equal subject.class.to_s, subject.name
    end

    should "set its enqueued job to an instance of Job" do
      assert_instance_of Qs::Job, subject.enqueued_job
    end

    should "know its enqueued job" do
      assert_equal({'something' => 'awesome'}, subject.enqueued_job.handler_args)
    end

    should "set `args` to an instance of Args" do
      assert_instance_of Qs::JobHandler::Args, subject.args
    end

    should "know its args" do
      assert_equal({'something' => 'awesome'}, subject.args.to_hash)
    end

  end

  class InitTests < BaseTests
    desc "that has had `init` called"
    setup do
      @handler = job_test_runner(MyTestApp::JobHandlers::CallbacksJob).handler
    end

    should "run the init! method" do
      assert_equal true, subject.init_was_called
    end

    should "run the init-callbacks" do
      assert_equal true, subject.before_init_called
      assert_equal true, subject.after_init_called
    end

  end

  class RunTests < InitTests
    desc "that has had `run` called"
    setup do
      @handler.run
    end

    should "run the run! method" do
      assert_equal true, subject.run_was_called
    end

    should "run the run-callbacks" do
      assert_equal true, subject.before_run_called
      assert_equal true, subject.after_run_called
    end

  end

  class FailureTests < BaseTests
    should "call the on_failure callback when failing during init" do
      handler = Qs::JobTestRunner.new(MyTestApp::JobHandlers::FailingInitJob).handler
      handler.init rescue nil

      assert_instance_of RuntimeError, handler.on_failure_called
    end

    should "call the on_failure callback when failing during run" do
      handler = job_test_runner(MyTestApp::JobHandlers::FailingRunJob).handler
      handler.run rescue nil

      assert_instance_of RuntimeError, handler.on_failure_called
    end

    should "call the on_failure callback when failing during a callback" do
      handler = job_test_runner(MyTestApp::JobHandlers::FailingCallbackJob).handler
      handler.run rescue nil

      assert_instance_of RuntimeError, handler.on_failure_called
    end

  end

  # Args utility class tests

  class ArgsTests < Assert::Context
    desc "Qs::JobHandler::Args"
    setup do
      @args = Qs::JobHandler::Args.new
    end
    subject{ @args }

    should have_instance_methods :to_hash, :hash

    should "allow indifferent access of it's keys" do
      subject[:something] = "awesome"

      assert_includes "something",    subject.keys
      assert_not_includes :something, subject.keys
      assert_equal "awesome",         subject[:something]
      assert_equal "awesome",         subject["something"]
    end

    should "allow passing an explicit nil" do
      assert_nothing_raised { Args.new(nil) }
    end

    should "stringify any hash keys that it was initialized with" do
      args = Args.new(:a => 1)

      assert_includes "a",    args.keys
      assert_not_includes :a, args.keys
      assert_equal 1,         args['a']
    end

  end

  class ArgsFormattingTests < ArgsTests
    setup do
      @hash = {
        'actually' => "try",
        'to'       => "test",
        'it'       => "like",
        "a"        => "boss"
      }
      @args = Args.new(@hash)
    end

    should "know its hash representation" do
      assert_equal @hash, subject.to_hash
      assert_equal @hash, subject.hash
    end

    should "use ArgsPrinter to generate its string representation" do
      assert_equal ArgsPrinter.new(@hash).to_s, subject.to_s
    end

  end

  # ArgsPrinter utility class tests

  class ArgsPrinterTests < Assert::Context
    desc "Qs::JobHandler::ArgsPrinter"
    setup do
      @max_size_int = 10 ** 24
      @too_long_int = 10 ** 26

      @max_size_symbol = ('a' * 24).to_sym
      @too_long_symbol = ('a' * 26).to_sym

      @max_size_string = ('a' * 25).to_s
      @too_long_string = ('a' * 26).to_s

      @printer = ArgsPrinter.new({})
    end
    subject{ @args }

    should have_instance_methods :to_s
  end

  class ArgsPrinterIntegerTests < ArgsPrinterTests
    desc "given an integer"

    should "return its string representation" do
      assert_equal "3", ArgsPrinter.new(3).to_s
    end

    should "truncate it's string representation when it's over 25 chars" do
      assert_equal "#{@max_size_int}...", ArgsPrinter.new(@too_long_int).to_s
    end

  end

  class ArgsPrinterFloatTests < ArgsPrinterTests
    desc "given a float"

    should "return its string representation" do
      assert_equal "30.0", ArgsPrinter.new(30.0).to_s
    end

    # The float test for a float over 25 chars is purposely left out
    # because it is a case that will not happen, ruby will automatically convert this
    # to scientific notation.

  end

  class ArgsPrinterSymbolTests < ArgsPrinterTests
    desc "given a symbol"

    should "return its string representation" do
      assert_equal ":something_amazing", ArgsPrinter.new(:something_amazing).to_s
    end

    should "truncate it's string representation when it's over 25 chars" do
      assert_equal ":#{@max_size_symbol}...", ArgsPrinter.new(@too_long_symbol).to_s
    end

  end

  class ArgsPrinterStringTests < ArgsPrinterTests
    desc "given a string"

    should "return its string representation" do
      assert_equal "\"string\"", ArgsPrinter.new("string").to_s
    end

    should "truncate it's string representation when it's over 25 chars" do
      assert_equal "\"#{@max_size_string}...\"", ArgsPrinter.new(@too_long_string).to_s
    end

  end

  class ArgsPrinterHashTests < ArgsPrinterTests
    desc "given a hash"

    should "accept any hash and return its string representation" do
      expected = "{ :hash => \"something\" }"
      assert_equal expected, ArgsPrinter.new({ :hash => "something" }).to_s
    end

    should "truncate the value's string representation when it's over 25 chars" do
      too_long_hash   = { :hash => @too_long_string }

      expected = "{ :hash => \"#{@max_size_string}...\" }"
      assert_equal expected, ArgsPrinter.new(too_long_hash).to_s
    end

    should "handle multiple key-values and sort by their keys" do
      mixed_hash = { :short => "test" , :long => @too_long_string }

      expected = "{ :long => \"#{@max_size_string}...\", :short => \"test\" }"
      assert_equal expected, ArgsPrinter.new(mixed_hash).to_s
    end

    should "handle nested hashes" do
      nested_hash = { :test_hash => { :second_hash => @too_long_string } }

      expected = "{ :test_hash => { :second_hash => \"#{@max_size_string}...\" } }"
      assert_equal expected, ArgsPrinter.new(nested_hash).to_s
    end

  end

  class ArgsPrinterArrayTests < ArgsPrinterTests
    desc "with an array"

    should "accept any array and return its string representation" do
      array = [1, 45.5, :symbol, "string", { :key => "value" }]

      expected = "[ 1, 45.5, :symbol, \"string\", { :key => \"value\" } ]"
      assert_equal expected, ArgsPrinter.new(array).to_s
    end

    should "truncate any item's string representation when it's over 25 chars" do
      array = [ 1, 45.5, :symbol, @too_long_string, { :key => @too_long_string } ]

      expected = "[ 1, 45.5, :symbol, \"#{@max_size_string}...\","\
                 " { :key => \"#{@max_size_string}...\" } ]"
      assert_equal expected, ArgsPrinter.new(array).to_s
    end

  end

end
