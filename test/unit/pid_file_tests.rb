require 'assert'
require 'qs/pid_file'

class Qs::PIDFile

  class UnitTests < Assert::Context
    desc "Qs::PIDFile"
    setup do
      @path = ROOT_PATH.join('tmp/pid_file_tests.pid').to_s
      @pid_file = Qs::PIDFile.new(@path)
    end
    teardown do
      FileUtils.rm_rf(@path)
    end
    subject{ @pid_file }

    should have_readers :path
    should have_imeths :pid, :write, :remove, :to_s

    should "know its path" do
      assert_equal @path, subject.path
    end

    should "default its path" do
      pid_file = Qs::PIDFile.new(nil)
      assert_equal '/dev/null', pid_file.path
    end

    should "know its string format" do
      assert_equal @path, subject.to_s
    end

    should "read a PID from its file" do
      pid = Factory.integer
      File.open(@path, 'w'){ |f| f.puts pid }
      assert_equal pid, subject.pid
    end

    should "raise an invalid error when it can't read from its file" do
      FileUtils.rm_rf(@path)
      assert_raises(InvalidError){ subject.pid }
    end

    should "raise an invalid error when the file doesn't have a PID in it" do
      File.open(@path, 'w'){ |f| f.puts '' }
      assert_raises(InvalidError){ subject.pid }
    end

    should "write the process PID to its file" do
      assert_false File.exists?(@path)
      subject.write
      assert_true File.exists?(@path)
      assert_equal "#{::Process.pid}\n", File.read(@path)
    end

    should "raise an invalid error when it can't write its file" do
      Assert.stub(File, :open){ raise "can't open file" }
      assert_raises(InvalidError){ subject.write }
    end

    should "remove its file" do
      FileUtils.touch(@path)
      assert_true File.exists?(@path)
      subject.remove
      assert_false File.exists?(@path)
    end

  end

end
