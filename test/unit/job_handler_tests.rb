require 'assert'
require 'qs/job_handler'

require 'qs/message_handler'

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
      assert_equal @runner.job,            subject.public_job
      assert_equal @runner.job.name,       subject.public_job_name
      assert_equal @runner.job.created_at, subject.public_job_created_at
    end

    should "have a custom inspect" do
      reference = '0x0%x' % (subject.object_id << 1)
      exp = "#<#{subject.class}:#{reference} " \
            "@job=#{@handler.public_job.inspect}>"
      assert_equal exp, subject.inspect
    end

  end

  class TestJobHandler
    include Qs::JobHandler

    def public_job;            job;            end
    def public_job_name;       job_name;       end
    def public_job_created_at; job_created_at; end
  end

  class FakeRunner
    attr_accessor :job

    def initialize
      @job = Factory.job
    end
  end

end
