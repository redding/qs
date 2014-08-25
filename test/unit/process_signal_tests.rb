require 'assert'
require 'qs/process_signal'

require 'qs/tmp_daemon'
require 'test/support/pid_file_spy'

class Qs::ProcessSignal

  class UnitTests < Assert::Context
    desc "Qs::ProcessSignal"
    setup do
      @daemon = TestDaemon.new
      @signal = Factory.string

      @pid_file_spy = PIDFileSpy.new(Factory.integer)
      Assert.stub(Qs::PIDFile, :new).with(@daemon.pid_file) do
        @pid_file_spy
      end

      @process_signal = Qs::ProcessSignal.new(@daemon, @signal)
    end
    subject{ @process_signal }

    should have_readers :signal, :pid
    should have_imeths :send

    should "know its signal and pid" do
      assert_equal @signal, subject.signal
      assert_equal @pid_file_spy.pid, subject.pid
    end

  end

  class SendTests < UnitTests
    desc "when sent"
    setup do
      @kill_called = false
      Assert.stub(::Process, :kill).with(@signal, @pid_file_spy.pid) do
        @kill_called = true
      end

      @process_signal.send
    end

    should "have used process kill to send the signal to the PID" do
      assert_true @kill_called
    end

  end

  class TestDaemon
    include Qs::TmpDaemon

    pid_file Factory.file_path

  end

end
