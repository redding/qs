require 'assert'
require 'qs/job_handler'

require 'qs'
require 'qs/message_handler'
require 'qs/test_runner'

module Qs::JobHandler

  class UnitTests < Assert::Context
    include Qs::JobHandler::TestHelpers

    desc "Qs::JobHandler"
    setup do
      Qs.init
      @handler_class = Class.new{ include Qs::JobHandler }
    end
    teardown do
      Qs.reset!
    end
    subject{ @handler_class }

    should "be a message handler" do
      assert_includes Qs::MessageHandler, subject
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @job     = Factory.job
      @runner  = test_runner(TestJobHandler, :message => @job)
      @handler = @runner.handler
    end
    subject{ @handler }

    should "have private helpers for accessing job attrs" do
      assert_equal @job,            subject.instance_eval{ job }
      assert_equal @job.name,       subject.instance_eval{ job_name }
      assert_equal @job.created_at, subject.instance_eval{ job_created_at }
    end

  end

  class TestHelpersTests < UnitTests
    desc "TestHelpers"
    setup do
      Qs.init
      job = Factory.job
      @args = {
        :message => job,
        :params  => job.params
      }

      context_class = Class.new{ include Qs::JobHandler::TestHelpers }
      @context = context_class.new
    end
    teardown do
      Qs.reset!
    end
    subject{ @context }

    should have_imeths :test_runner, :test_handler

    should "build a test runner for a given handler class" do
      runner = subject.test_runner(@handler_class, @args)

      assert_kind_of Qs::TestRunner, runner
      assert_equal @handler_class,   runner.handler_class
      assert_equal @args[:message],  runner.message
      assert_equal @args[:params],   runner.params
    end

    should "return an initialized handler instance" do
      handler = subject.test_handler(@handler_class, @args)
      assert_kind_of @handler_class, handler

      exp = subject.test_runner(@handler_class, @args).handler
      assert_equal exp, handler
    end

  end

  class TestJobHandler
    include Qs::JobHandler

  end

end
