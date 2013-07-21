require 'assert'
require 'qs/cli'

require 'qs/daemon'

class Qs::Config

  class BaseTests < Assert::Context
    desc "Qs::Config"
    setup do
      @file_path = SUPPORT_PATH.join('config_files/valid.qs')
      @config    = Qs::Config.new(@file_path)
    end
    subject{ @config }

    should have_imeths :run, :daemon
    should have_cmeths :parse

    should "set the daemon with #run" do
      my_daemon = Qs::Daemon.new
      subject.run my_daemon
      assert_equal my_daemon, subject.daemon
    end

    should "return the daemon set with `run` using #daemon" do
      assert_instance_of Qs::Daemon, subject.daemon
    end

    should "build a new config file and return it with #parse" do
      config = Qs::Config.parse(@file_path)
      assert_instance_of Qs::Config, config
    end

  end

  class WithoutQsTests < BaseTests
    desc "with a path string that doesn't end in .qs, but the file does"
    setup do
      @file_path = SUPPORT_PATH.join('config_files/valid')
    end

    should "find the file and parse it" do
      config = nil
      assert_nothing_raised{ config = Qs::Config.new(@file_path) }
      assert_instance_of Qs::Daemon, config.daemon
    end

  end

  class NoFileTests < BaseTests
    desc "with a path string for a file that doesn't exist"
    setup do
      @file_path = SUPPORT_PATH.join('dont_exist')
    end

    should "raise a NoConfigFile error" do
      qs_file_path = "#{@file_path}.qs"
      exception = nil
      begin; Qs::Config.new(qs_file_path); rescue Exception => exception; end
      assert_instance_of Qs::Config::NoConfigFileError, exception
      expected_message = "A configuration file couldn't be found at: " \
                         "#{qs_file_path.to_s.inspect}"
      assert_equal expected_message, exception.message
    end

    should "raise a NoConfigFile error with the original path, " \
           "even when it tries to add on the .qs" do
      exception = nil
      begin; Qs::Config.new(@file_path); rescue Exception => exception; end
      assert_instance_of Qs::Config::NoConfigFileError, exception
      expected_message = "A configuration file couldn't be found at: " \
                         "#{@file_path.to_s.inspect}"
      assert_equal expected_message, exception.message
    end

  end

  class NoRunTests < BaseTests
    desc "with a config file that doesn't call `run`"
    setup do
      @file_path = SUPPORT_PATH.join('config_files/empty.qs')
      @config    = Qs::Config.new(@file_path)
    end

    should "raise a NoDaemon error" do
      exception = nil
      begin; subject.daemon; rescue Exception => exception; end
      assert_instance_of Qs::Config::NoDaemonError, exception
      expected_message = "Configuration file #{@file_path.to_s.inspect} " \
                         "didn't call `run` with a Qs::Daemon"
      assert_equal expected_message, exception.message
    end

  end

  class InvalidDaemonTests < BaseTests
    desc "with a config file that calls `run` but not with a Qs::Daemon"
    setup do
      @file_path = SUPPORT_PATH.join('config_files/invalid.qs')
      @config    = Qs::Config.new(@file_path)
    end

    should "raise a NoDaemon error" do
      exception = nil
      begin; subject.daemon; rescue Exception => exception; end
      assert_instance_of Qs::Config::NoDaemonError, exception
      expected_message = "Configuration file #{@file_path.to_s.inspect} " \
                         "called `run` without a Qs::Daemon"
      assert_equal expected_message, exception.message
    end

  end

end
