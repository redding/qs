require 'assert'
require 'qs/io_pipe'

require 'thread'

class Qs::IOPipe

  class UnitTests < Assert::Context
    desc "Qs::IOPipe"
    setup do
      @io_pipe = Qs::IOPipe.new
    end
    subject{ @io_pipe }

    should have_readers :reader, :writer
    should have_imeths :setup, :teardown
    should have_imeths :read, :write, :wait

    should "default its reader and writer" do
      assert_same NULL, subject.reader
      assert_same NULL, subject.writer
    end

    should "change its reader/writer to an IO pipe when setup" do
      subject.setup
      assert_not_same NULL, subject.reader
      assert_not_same NULL, subject.writer
      assert_instance_of IO, subject.reader
      assert_instance_of IO, subject.writer
    end

    should "close its reader/writer and set them to defaults when torn down" do
      subject.setup
      reader = subject.reader
      writer = subject.writer

      subject.teardown
      assert_true reader.closed?
      assert_true writer.closed?
      assert_same NULL, subject.reader
      assert_same NULL, subject.writer
    end

    should "be able to read/write values" do
      subject.setup

      value = Factory.string
      subject.write(value)
      assert_equal value, subject.read
    end

    should "be able to wait until there is something to read" do
      subject.setup

      result = nil
      thread = Thread.new{ result = subject.wait }
      thread.join(0.1)
      assert_equal 'sleep', thread.status

      subject.write(Factory.string)
      thread.join
      assert_false thread.status
      assert_equal subject, result
    end

  end

end
