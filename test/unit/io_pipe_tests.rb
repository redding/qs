require 'assert'
require 'qs/io_pipe'

require 'thread'

class Qs::IOPipe

  class UnitTests < Assert::Context
    desc "Qs::IOPipe"
    setup do
      # mimic how IO.select responds
      @io_select_response    = Factory.boolean ? [[NULL], [], []] : nil
      @io_select_called_with = nil
      Assert.stub(IO, :select) do |*args|
        @io_select_called_with = args
        @io_select_response
      end

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

      value = Factory.string(NUMBER_OF_BYTES)
      subject.write(value)
      assert_equal value, subject.read
    end

    should "only read/write a fixed number of bytes" do
      subject.setup

      value = Factory.string
      subject.write(value)
      assert_equal value[0, NUMBER_OF_BYTES], subject.read
    end

    should "be able to wait until there is something to read" do
      subject.setup

      result = subject.wait
      exp = [[subject.reader], nil, nil, nil]
      assert_equal exp, @io_select_called_with
      assert_equal !!@io_select_response, result

      timeout = Factory.integer
      subject.wait(timeout)
      exp = [[subject.reader], nil, nil, timeout]
      assert_equal exp, @io_select_called_with
    end

  end

end
