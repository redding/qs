require 'assert'
require 'qs/dispatch_job_handler'

require 'qs/job_handler'

module Qs::DispatchJobHandler

  class UnitTests < Assert::Context
    include Qs::JobHandler::TestHelpers

    desc "Qs::DispatchJobHandler"
    setup do
      Qs.init
      @handler_class = Class.new do
        include Qs::DispatchJobHandler
      end
    end
    teardown do
      Qs.reset!
    end
    subject{ @handler_class }

    should "be a job handler" do
      assert_includes Qs::JobHandler, subject
    end

  end

  class InitSetupTests < UnitTests
    desc "when init"
    setup do
      @job = Factory.dispatch_job(:publisher => Factory.string)
      @queue_names = Factory.integer(3).times.map{ Factory.string }
      Assert.stub(Qs, :event_subscribers){ @queue_names }

      @push_calls = []
      Assert.stub(Qs, :push){ |*args| @push_calls << PushCall.new(*args) }

      @logger_spy  = LoggerSpy.new
      @runner_args = {
        :job    => @job,
        :params => @job.params,
        :logger => @logger_spy
      }
    end
    subject{ @handler }

  end

  class InitTests < InitSetupTests
    setup do
      @runner  = test_runner(@handler_class, @runner_args)
      @handler = @runner.handler
    end

    should "know its event and subscribed queue names" do
      assert_equal @job.event,   subject.event
      assert_equal @queue_names, subject.subscribed_queue_names
    end

  end

  class RunTests < InitTests
    desc "and run"
    setup do
      @runner.run
    end

    should "push the events payload to all of the subscribed queue names" do
      assert_equal @queue_names, @push_calls.map(&:queue_name)
      exp = Qs::Payload.event_hash(subject.event)
      assert_equal [exp], @push_calls.map(&:payload).uniq
    end

    should "log the queues it dispatches to" do
      exp = [
        "Dispatching #{subject.event.route_name}",
        "  params:       #{subject.event.params.inspect}",
        "  publisher:    #{subject.event.publisher}",
        "  published at: #{subject.event.published_at}",
        "Found #{subject.subscribed_queue_names.size} subscribed queue(s):",
        @queue_names.map{ |queue_name| "  => #{queue_name}" }
      ].flatten.join("\n")
      assert_equal exp, @logger_spy.messages.join("\n")
    end

  end

  class RunWithDispatchesThatErrorTests < InitSetupTests
    desc "and run with dispatches that error"
    setup do
      @fail_queue_names = Factory.integer(3).times.map{ Factory.string }
      @dispatch_error = RuntimeError.new(Factory.text)
      payload_hash = Qs::Payload.event_hash(@job.event)
      @fail_queue_names.each do |queue_name|
        Assert.stub(Qs, :push).with(queue_name, payload_hash) do
          raise @dispatch_error
        end
      end

      @success_queue_names = @queue_names.dup
      # add the fail queue names to the front to test that they don't cause
      # the other queues not to be dispatched to
      @queue_names = @fail_queue_names + @success_queue_names

      @runner  = test_runner(@handler_class, @runner_args)
      @handler = @runner.handler

      @exception = nil
      begin; @runner.run; rescue => @exception; end
    end

    should "raise a dispatch error after trying to dispatch to every queue" do
      assert_equal @success_queue_names, @push_calls.map(&:queue_name)

      assert_instance_of DispatchError, @exception
      descriptions = @fail_queue_names.map do |queue_name|
        "#{queue_name} - #{@dispatch_error.class}: #{@dispatch_error.message}"
      end
      exp = "#{subject.event.route_name} event wasn't dispatched to:\n" \
            "  #{descriptions.join("\n  ")}"
      assert_equal exp, @exception.message
      exp = @fail_queue_names.map do |queue_name|
        FailedDispatch.new(queue_name, @dispatch_error)
      end
      assert_equal exp, @exception.failed_dispatches
    end

    should "log the queues it dispatches to and the errors it encounters" do
      exp = [
        "Dispatching #{subject.event.route_name}",
        "  params:       #{subject.event.params.inspect}",
        "  publisher:    #{subject.event.publisher}",
        "  published at: #{subject.event.published_at}",
        "Found #{subject.subscribed_queue_names.size} subscribed queue(s):",
        @fail_queue_names.map{ |queue_name| "  => #{queue_name} (failed)" },
        @success_queue_names.map{ |queue_name| "  => #{queue_name}" },
        "Failed to dispatch the event to #{@fail_queue_names.size} subscribed queues",
        @fail_queue_names.map do |queue_name|
          [ queue_name,
            "  #{@dispatch_error.class}: #{@dispatch_error.message}",
            "  #{@dispatch_error.backtrace.first}"
          ]
        end
      ].flatten.join("\n")
      assert_equal exp, @logger_spy.messages.join("\n")
    end

  end

  PushCall = Struct.new(:queue_name, :payload)

  class LoggerSpy
    attr_reader :messages

    def initialize
      @messages = []
    end

    def info(message); @messages << message; end
  end

end
