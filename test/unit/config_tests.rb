require 'assert'
require 'qs/cli'

require 'qs/daemon'

class Qs::Config

  class UnitTests < Assert::Context
    desc "Qs::Config"
    setup do
      @file_path = SUPPORT_PATH.join('config_files/valid.qs')
      @config    = Qs::Config.new(@file_path)
    end
    subject{ @config }

    should have_imeths :run, :daemon

    should "set its daemon with #run" do
      my_daemon_class = Class.new{ include Qs::Daemon }
      my_daemon = my_daemon_class.new
      subject.run my_daemon
      assert_equal my_daemon, subject.daemon
    end

    should "return the daemon set with `run` using #daemon" do
      # `MyDaemon` is defined in `valid.qs`
      assert_instance_of MyDaemon, subject.daemon
    end

  end

  class WithoutQsTests < UnitTests
    desc "with a path string that doesn't end in .qs, but the file does"
    setup do
      @file_path = SUPPORT_PATH.join('config_files/valid')
    end

    should "find the file and eval it" do
      config = nil
      assert_nothing_raised{ config = Qs::Config.new(@file_path) }
      # `MyDaemon` is defined in `valid.qs`
      assert_instance_of MyDaemon, config.daemon
    end

  end

  class NoFileTests < UnitTests
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

  class NoRunTests < UnitTests
    desc "with a config file that doesn't call `run`"
    setup do
      @file_path = SUPPORT_PATH.join('config_files/empty.qs')
    end

    should "raise a NoDaemon error" do
      exception = nil
      begin; Qs::Config.new(@file_path); rescue Exception => exception; end
      assert_instance_of Qs::Config::NoDaemonError, exception
      expected_message = "Configuration file #{@file_path.to_s.inspect} " \
                         "didn't call `run` with a Qs::Daemon"
      assert_equal expected_message, exception.message
    end

  end

  class InvalidDaemonTests < UnitTests
    desc "with a config file that calls `run` but not with a daemon"
    setup do
      @file_path = SUPPORT_PATH.join('config_files/invalid.qs')
    end

    should "raise a NoDaemon error" do
      exception = nil
      begin; Qs::Config.new(@file_path); rescue Exception => exception; end
      assert_instance_of Qs::Config::NoDaemonError, exception
      expected_message = "Configuration file #{@file_path.to_s.inspect} " \
                         "called `run` without a Qs::Daemon"
      assert_equal expected_message, exception.message
    end

  end

end
