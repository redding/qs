require 'assert'
require 'qs/message_handler'

module Qs::MessageHandler

  class UnitTests < Assert::Context
    desc "Qs::MessageHandler"
    setup do
      @handler_class = Class.new{ include Qs::MessageHandler }
    end
    subject{ @handler_class }

    should have_imeths :timeout
    should have_imeths :before_callbacks, :after_callbacks
    should have_imeths :before_init_callbacks, :after_init_callbacks
    should have_imeths :before_run_callbacks,  :after_run_callbacks
    should have_imeths :before, :after
    should have_imeths :before_init, :after_init
    should have_imeths :before_run,  :after_run
    should have_imeths :prepend_before, :prepend_after
    should have_imeths :prepend_before_init, :prepend_after_init
    should have_imeths :prepend_before_run,  :prepend_after_run

    should "allow reading/writing its timeout" do
      assert_nil subject.timeout
      value = Factory.integer
      subject.timeout(value)
      assert_equal value, subject.timeout
    end

    should "convert timeout values to floats" do
      value = Factory.float.to_s
      subject.timeout(value)
      assert_equal value.to_f, subject.timeout
    end

    should "return an empty array by default using `before_callbacks`" do
      assert_equal [], subject.before_callbacks
    end

    should "return an empty array by default using `after_callbacks`" do
      assert_equal [], subject.after_callbacks
    end

    should "return an empty array by default using `before_init_callbacks`" do
      assert_equal [], subject.before_init_callbacks
    end

    should "return an empty array by default using `after_init_callbacks`" do
      assert_equal [], subject.after_init_callbacks
    end

    should "return an empty array by default using `before_run_callbacks`" do
      assert_equal [], subject.before_run_callbacks
    end

    should "return an empty array by default using `after_run_callbacks`" do
      assert_equal [], subject.after_run_callbacks
    end

    should "append a block to the before callbacks using `before`" do
      subject.before_callbacks << proc{ Factory.string }
      block = Proc.new{ Factory.string }
      subject.before(&block)
      assert_equal block, subject.before_callbacks.last
    end

    should "append a block to the after callbacks using `after`" do
      subject.after_callbacks << proc{ Factory.string }
      block = Proc.new{ Factory.string }
      subject.after(&block)
      assert_equal block, subject.after_callbacks.last
    end

    should "append a block to the before init callbacks using `before_init`" do
      subject.before_init_callbacks << proc{ Factory.string }
      block = Proc.new{ Factory.string }
      subject.before_init(&block)
      assert_equal block, subject.before_init_callbacks.last
    end

    should "append a block to the after init callbacks using `after_init`" do
      subject.after_init_callbacks << proc{ Factory.string }
      block = Proc.new{ Factory.string }
      subject.after_init(&block)
      assert_equal block, subject.after_init_callbacks.last
    end

    should "append a block to the before run callbacks using `before_run`" do
      subject.before_run_callbacks << proc{ Factory.string }
      block = Proc.new{ Factory.string }
      subject.before_run(&block)
      assert_equal block, subject.before_run_callbacks.last
    end

    should "append a block to the after run callbacks using `after_run`" do
      subject.after_run_callbacks << proc{ Factory.string }
      block = Proc.new{ Factory.string }
      subject.after_run(&block)
      assert_equal block, subject.after_run_callbacks.last
    end

    should "prepend a block to the before callbacks using `prepend_before`" do
      subject.before_callbacks << proc{ Factory.string }
      block = Proc.new{ Factory.string }
      subject.prepend_before(&block)
      assert_equal block, subject.before_callbacks.first
    end

    should "prepend a block to the after callbacks using `prepend_after`" do
      subject.after_callbacks << proc{ Factory.string }
      block = Proc.new{ Factory.string }
      subject.prepend_after(&block)
      assert_equal block, subject.after_callbacks.first
    end

    should "prepend a block to the before init callbacks using `prepend_before_init`" do
      subject.before_init_callbacks << proc{ Factory.string }
      block = Proc.new{ Factory.string }
      subject.prepend_before_init(&block)
      assert_equal block, subject.before_init_callbacks.first
    end

    should "prepend a block to the after init callbacks using `prepend_after_init`" do
      subject.after_init_callbacks << proc{ Factory.string }
      block = Proc.new{ Factory.string }
      subject.prepend_after_init(&block)
      assert_equal block, subject.after_init_callbacks.first
    end

    should "prepend a block to the before run callbacks using `prepend_before_run`" do
      subject.before_run_callbacks << proc{ Factory.string }
      block = Proc.new{ Factory.string }
      subject.prepend_before_run(&block)
      assert_equal block, subject.before_run_callbacks.first
    end

    should "prepend a block to the after run callbacks using `prepend_after_run`" do
      subject.after_run_callbacks << proc{ Factory.string }
      block = Proc.new{ Factory.string }
      subject.prepend_after_run(&block)
      assert_equal block, subject.after_run_callbacks.first
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @runner  = FakeRunner.new
      @handler = TestMessageHandler.new(@runner)
    end
    subject{ @handler }

    should have_imeths :init, :init!, :run, :run!

    should "know its params and logger" do
      assert_equal @runner.params, subject.public_params
      assert_equal @runner.logger, subject.public_logger
    end

    should "call `init!` and its before/after init callbacks using `init`" do
      subject.init
      assert_equal 1, subject.first_before_init_call_order
      assert_equal 2, subject.second_before_init_call_order
      assert_equal 3, subject.init_call_order
      assert_equal 4, subject.first_after_init_call_order
      assert_equal 5, subject.second_after_init_call_order
    end

    should "call `run!` and its before/after run callbacks using `run`" do
      subject.run
      assert_equal 1, subject.first_before_run_call_order
      assert_equal 2, subject.second_before_run_call_order
      assert_equal 3, subject.run_call_order
      assert_equal 4, subject.first_after_run_call_order
      assert_equal 5, subject.second_after_run_call_order
    end

    should "know if it is equal to another message handler" do
      handler = TestMessageHandler.new(@runner)
      assert_equal handler, subject

      handler = Class.new{ include Qs::MessageHandler }.new(Factory.string)
      assert_not_equal handler, subject
    end

  end

  class TestMessageHandler
    include Qs::MessageHandler

    attr_reader :first_before_init_call_order, :second_before_init_call_order
    attr_reader :first_after_init_call_order, :second_after_init_call_order
    attr_reader :first_before_run_call_order, :second_before_run_call_order
    attr_reader :first_after_run_call_order, :second_after_run_call_order
    attr_reader :init_call_order, :run_call_order

    before_init{ @first_before_init_call_order = next_call_order }
    before_init{ @second_before_init_call_order = next_call_order }

    after_init{ @first_after_init_call_order = next_call_order }
    after_init{ @second_after_init_call_order = next_call_order }

    before_run{ @first_before_run_call_order = next_call_order }
    before_run{ @second_before_run_call_order = next_call_order }

    after_run{ @first_after_run_call_order = next_call_order }
    after_run{ @second_after_run_call_order = next_call_order }

    def init!
      @init_call_order = next_call_order
    end

    def run!
      @run_call_order = next_call_order
    end

    def public_params; params; end
    def public_logger; logger; end

    private

    def next_call_order
      @order ||= 0
      @order += 1
    end
  end

  class FakeRunner
    attr_accessor :params, :logger

    def initialize
      @params = Factory.string
      @logger = Factory.string
    end
  end

end
