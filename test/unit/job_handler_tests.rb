require 'assert'
require 'qs/job_handler'

require 'qs'
require 'qs/message_handler'
require 'qs/test_runner'

module Qs::JobHandler

  class UnitTests < Assert::Context
    desc "Qs::JobHandler"
    setup do
      @handler_class = Class.new{ include Qs::JobHandler }
    end
    subject{ @handler_class }

    should "be a message handler" do
      assert_includes Qs::MessageHandler, subject
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @runner  = FakeRunner.new
      @handler = TestJobHandler.new(@runner)
    end
    subject{ @handler }

    should "know its job, job name and job created at" do
      assert_equal @runner.message,               subject.public_job
      assert_equal subject.public_job.name,       subject.public_job_name
      assert_equal subject.public_job.created_at, subject.public_job_created_at
    end

    should "have a custom inspect" do
      reference = '0x0%x' % (subject.object_id << 1)
      exp = "#<#{subject.class}:#{reference} " \
            "@job=#{@handler.public_job.inspect}>"
      assert_equal exp, subject.inspect
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

    def public_job;            job;            end
    def public_job_name;       job_name;       end
    def public_job_created_at; job_created_at; end
  end

  class FakeRunner
    attr_accessor :message

    def initialize
      @message = Factory.job
    end
  end

end
