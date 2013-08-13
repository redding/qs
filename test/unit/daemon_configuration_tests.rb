require 'assert'
require 'qs/daemon'

class Qs::Daemon::Configuration

  class UnitTests < Assert::Context
    desc "Qs::Daemon::Configuration"
    setup do
      @configuration = Qs::Daemon::Configuration.new
    end
    subject{ @configuration }

    should have_imeths :pid_file
    should have_imeths :min_workers, :max_workers
    should have_imeths :wait_timeout, :shutdown_timeout

    should have_accessors :init_procs, :error_procs, :queue

    should have_imeths :valid?, :validate!, :mappings

    should "apply a hash's values when initialized" do
      configuration = Qs::Daemon::Configuration.new :pid_file => 'test.pid'
      assert_equal 'test.pid', configuration.pid_file
    end

    should "build a new Queue when initialized" do
      assert_instance_of Qs::Queue, subject.queue
    end

    should "default it's pid file" do
      assert_equal 'qs.pid', subject.pid_file
    end

    should "default it's min and max workers" do
      assert_equal 4, subject.min_workers
      assert_equal 4, subject.max_workers
    end

    should "default it's wait and shutdown timeout" do
      assert_equal 5,   subject.wait_timeout
      assert_equal nil, subject.shutdown_timeout
    end

    should "default it's init and error procs" do
      assert_equal [], subject.init_procs
      assert_equal [], subject.error_procs
    end

    should "not be valid until it's validated" do
      assert_equal false, subject.valid?
      subject.validate!
      assert_equal true, subject.valid?
    end

    should "return it's queue's mappings with #mappings" do
      subject.queue.mappings = [ mock('Mapping') ]
      assert_equal subject.queue.mappings, subject.mappings
    end

  end

  class ValidateTests < UnitTests
    desc "when validated"
    setup do
      @queue = Qs::Queue.new
      @configuration.queue = @queue
    end

    should "call it's init procs" do
      init_proc_called = false
      @configuration.init_procs << proc{ init_proc_called = true }
      assert_nothing_raised{ subject.validate! }
      assert_equal true, init_proc_called
    end

    should "call `validate!` on any mappings" do
      # TODO - switch out mock / stub with actual behavior or at least behavior
      # more true to the implementation
      @queue.mappings = [
        mock('Mapping').tap{ |m| m.stubs(:validate!).raises(StandardError) }
      ]
      assert_raises(StandardError){ subject.validate! }
    end

    should "only be done once" do
      assert_nothing_raised{ subject.validate! }
      assert_equal true, subject.valid?
      @configuration.init_procs << proc{ raise("shouldn't be called") }
      assert_nothing_raised{ subject.validate! }
    end

  end

end
