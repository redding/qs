require 'assert'
require 'qs/runner'

require 'qs/job_handler'
require 'qs/logger'

class Qs::Runner

  class UnitTests < Assert::Context
    desc "Qs::Runner"
    setup do
      @runner_class = Qs::Runner
    end
    subject{ @runner_class }

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @handler_class = TestJobHandler
      @runner = @runner_class.new(@handler_class)
    end
    subject{ @runner }

    should have_readers :handler_class, :handler
    should have_readers :logger, :message, :params
    should have_imeths :run

    should "know its handler class and handler" do
      assert_equal @handler_class, subject.handler_class
      assert_instance_of @handler_class, subject.handler
    end

    should "default its attrs" do
      assert_instance_of Qs::NullLogger, subject.logger
      assert_nil subject.message
      assert_equal({}, subject.params)
    end

    should "know its attrs" do
      args = {
        :logger  => Factory.string,
        :message => Factory.string,
        :params  => Factory.string
      }

      runner = @runner_class.new(@handler_class, args)

      assert_equal args[:logger],  runner.logger
      assert_equal args[:message], runner.message
      assert_equal args[:params],  runner.params
    end

    should "not implement its run method" do
      assert_raises(NotImplementedError){ subject.run }
    end

  end

  class TestJobHandler
    include Qs::JobHandler

  end

end
