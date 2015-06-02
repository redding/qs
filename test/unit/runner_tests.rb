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
    should have_readers :message, :params, :logger
    should have_imeths :run

    should "know its handler class and handler" do
      assert_equal @handler_class, subject.handler_class
      assert_instance_of @handler_class, subject.handler
    end

    should "not set its message, params or logger by default" do
      assert_nil subject.message
      assert_equal({}, subject.params)
      assert_instance_of Qs::NullLogger, subject.logger
    end

    should "allow passing a message, params and logger" do
      args = {
        :message => Factory.string,
        :params  => Factory.string,
        :logger  => Factory.string
      }
      runner = @runner_class.new(@handler_class, args)
      assert_equal args[:message], runner.message
      assert_equal args[:params],  runner.params
      assert_equal args[:logger],  runner.logger
    end

    should "raise a not implemented error when run" do
      assert_raises(NotImplementedError){ subject.run }
    end

  end

  class TestJobHandler
    include Qs::JobHandler
  end

end
