require 'assert'
require 'qs/config_file'

class Qs::ConfigFile

  class UnitTests < Assert::Context
    desc "Qs::ConfigFile"
    setup do
      @file_path = ROOT_PATH.join('test/support/config.qs')
      @config_file = Qs::ConfigFile.new(@file_path)
    end
    subject{ @config_file }

    should have_readers :daemon
    should have_imeths :run

    should "know its daemon" do
      assert_instance_of ConfigFileTestDaemon, subject.daemon
    end

    should "define constants in the file at the top-level binding" do
      assert_not_nil defined?(::TestConstant)
    end

    should "set its daemon using run" do
      fake_daemon = Factory.string
      subject.run fake_daemon
      assert_equal fake_daemon, subject.daemon
    end

    should "allow passing a path without the extension" do
      file_path = ROOT_PATH.join('test/support/config')
      config_file = nil

      assert_nothing_raised do
        config_file = Qs::ConfigFile.new(file_path)
      end
      assert_instance_of ConfigFileTestDaemon, config_file.daemon
    end

    should "raise no config file error when the file doesn't exist" do
      assert_raises(NoConfigFileError) do
        Qs::ConfigFile.new(Factory.file_path)
      end
    end

    should "raise a no daemon error when the file doesn't call run" do
      file_path = ROOT_PATH.join('test/support/config_no_run.qs')
      assert_raises(NoDaemonError){ Qs::ConfigFile.new(file_path) }
    end

    should "raise a no daemon error when the file provides an invalid daemon" do
      file_path = ROOT_PATH.join('test/support/config_invalid_run.qs')
      assert_raises(NoDaemonError){ Qs::ConfigFile.new(file_path) }
    end

  end

end
