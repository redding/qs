require 'assert'
require 'qs/logger'

class Qs::Logger

  class UnitTests < Assert::Context
    desc "Qs::Logger"
    setup do
      @real_logger = Factory.string
    end
    subject{ Qs::Logger }

    should "set its loggers correctly in summary mode" do
      logger = subject.new(@real_logger, false)
      assert_equal @real_logger, logger.summary
      assert_instance_of Qs::NullLogger, logger.verbose
    end

    should "set its loggers correctly in verbose mode" do
      logger = subject.new(@real_logger, true)
      assert_instance_of Qs::NullLogger, logger.summary
      assert_equal @real_logger, logger.verbose
    end

  end

  class NullLoggerTests < Assert::Context
    desc "Qs::NullLogger"
    setup do
      @null_logger = Qs::NullLogger.new
    end
    subject{ @null_logger }

    should have_imeths :debug, :info, :error

  end

end
