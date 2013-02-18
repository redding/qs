require 'assert'
require 'qs'

module Qs

  class BaseTests < Assert::Context
    desc "the Qs module"
    subject { Qs }

    should have_imeths :config, :configure, :init

    should "know its config singleton" do
      assert_same Config, subject.config
    end

    # Note: don't really need to explicitly test the configure/init meths
    # nothing runs as expected if they aren't working

  end

  class ConfigTests < Assert::Context
    desc "the Qs Config singleton"
    subject { Config }

    should have_imeths :timeout, :logger
    should have_imeths :default_timeout, :null_logger

    should "know its default_timeout" do
      assert_equal 300, subject.default_timeout
    end

    should "know its null logger" do
      assert_kind_of ::Logger, subject.null_logger
    end

    should "use its default timeout for its timeout setting (by default)" do
      assert_equal subject.default_timeout, subject.timeout
    end

    should "use its null logger for its logger setting (by default)" do
      assert_same subject.null_logger, subject.logger
    end

  end

end
