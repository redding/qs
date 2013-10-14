require 'assert'
require 'qs/daemon'

require 'dat-worker-pool/worker_pool_spy'
require 'thread'

module Qs::Daemon

  class UnitTests < Assert::Context
    desc "Qs::Daemon"
    setup do
      @shutdown_timeout = 15
      @daemon_class = Class.new{ include Qs::Daemon }
      @daemon_class.shutdown_timeout @shutdown_timeout
      @queue = @daemon_class.configuration.queue
      @daemon = @daemon_class.new
    end
    subject{ @daemon }

    should have_cmeths :configuration
    should have_cmeths :queue
    should have_cmeths :pid_file
    should have_cmeths :min_workers, :max_workers, :workers
    should have_cmeths :wait_timeout, :shutdown_timeout

    should have_readers :queue_name, :pid_file, :logger
    should have_writers :check_for_signals_proc

    should have_imeths :start, :stop, :halt
    should have_imeths :running?

    should "return it's configuration's pid file with #pid_file" do
      assert_equal @daemon_class.configuration.pid_file, subject.pid_file
    end

    should "return it's configuration's queue's name with #queue_name" do
      assert_equal @queue.name, subject.queue_name
    end

    should "return it's queue's logger with #logger" do
      assert_equal @queue.logger, subject.logger
    end

    should "be stopped by default" do
      assert_not subject.running?
    end

  end

  class StartingAndStoppingTests < UnitTests
    setup do
      @worker_pool_spy = DatWorkerPool::WorkerPoolSpy.new
      DatWorkerPool.stubs(:new).tap do |s|
        s.with(@daemon_class.min_workers, @daemon_class.max_workers)
        s.returns(@worker_pool_spy)
      end
    end
    teardown do
      @daemon.stop rescue false
      DatWorkerPool.unstub(:new)
    end
  end

  class StartTests < StartingAndStoppingTests
    desc "when started"
    setup do
      @thread = @daemon.start
    end

    should "be running" do
      assert subject.running?
    end

    should "return the daemon's work loop thread" do
      assert_instance_of Thread, @thread
      assert @thread.alive?
    end

  end

  class CheckSignalProcTests < StartingAndStoppingTests
    desc "when given a check for signals proc and started"
    setup do
      @daemon_class.wait_timeout 0
      @daemon = @daemon_class.new
      @check_for_signals_proc_called = 0
      @daemon.check_for_signals_proc = proc{ @check_for_signals_proc_called += 1 }
      @thread = @daemon.start
    end

    should "call `check_for_signals_proc` as part of it's work loop" do
      @thread.join(0.1)
      assert @check_for_signals_proc_called > 0
    end

  end

  class WorkLoopWithWorkTests < StartingAndStoppingTests
    desc "when started with a worker available and work on the queue, it"
    setup do
      @worker_pool_spy.worker_available = true
      @queue.stubs(:fetch_job).tap do |s|
        s.with(@daemon_class.configuration.wait_timeout)
        s.returns('test')
      end
      @thread = @daemon.start
    end

    should "fetch jobs from the queue and add them to the worker pool" do
      @thread.join(0.1)
      assert_includes 'test', @worker_pool_spy.work_items
    end

  end

  class WorkLoopNoWorkersAvailableTests < StartingAndStoppingTests
    desc "when it's started but there are no workers available"
    setup do
      @worker_pool_spy.worker_available = false
      @queue.stubs(:fetch_job).raises("shouldn't be called")
      @thread = @daemon.start
    end

    should "not add any jobs to the worker pool" do
      @thread.join(0.1)
      assert_equal 0, @worker_pool_spy.work_items.size
    end

  end

  class WorkLoopQueueNotEmptyTests < StartingAndStoppingTests
    desc "when it's started but the worker pool's queue isn't empty"
    setup do
      @worker_pool_spy.add_work 'job'
      @queue.stubs(:fetch_job).raises("shouldn't be called")
      @thread = @daemon.start
    end

    should "not fetch any jobs and add them to the worker pool" do
      @thread.join(0.1)
      assert_equal 1, @worker_pool_spy.work_items.size
    end

  end

  class StopTests < StartingAndStoppingTests
    desc "when stopped"
    setup do
      @thread = @daemon.start
      @daemon.stop true
    end

    should "have shutdown the worker pool" do
      assert @worker_pool_spy.shutdown_called
      assert_equal @shutdown_timeout, @worker_pool_spy.shutdown_timeout
    end

    should "no longer be running" do
      assert_not subject.running?
    end

    should "stop the daemon's work loop thread" do
      assert_not @thread.alive?
    end

  end

  class HaltTests < StartingAndStoppingTests
    desc "when halted"
    setup do
      @thread = @daemon.start
      @daemon.halt true
    end

    should "not have shutdown the worker pool" do
      assert_not @worker_pool_spy.shutdown_called
    end

    should "no longer be running" do
      assert_not subject.running?
    end

    should "stop the daemon's work loop thread" do
      assert_not @thread.alive?
    end

  end

  class ValidateConfigurationTests < UnitTests
    desc "with an invalid config"
    setup do
      @daemon_class.configuration.stubs(:validate!).raises(StandardError)
    end
    teardown do
      @daemon_class.configuration.unstub(:validate!)
    end

    should "validate the configuration when initialized" do
      assert_raises(StandardError){ @daemon_class.new }
    end

  end

  class ClassMethodTests < UnitTests
    desc "class"
    subject{ @daemon_class }

    should "return an instance of a Configuration with #configuration" do
      assert_instance_of Configuration, subject.configuration
    end

    should "allow reading/writing the configuration's queue" do
      test_queue = Qs::Queue.new
      assert_nothing_raised{ subject.queue test_queue }
      assert_equal test_queue, subject.queue
    end

    should "allow reading/writing the configuration's pid file" do
      assert_nothing_raised{ subject.pid_file 'test.pid' }
      assert_equal 'test.pid', subject.pid_file
    end

    should "allow reading/writing the configuration's min workers" do
      assert_nothing_raised{ subject.min_workers 2 }
      assert_equal 2, subject.min_workers
    end

    should "allow reading/writing the configuration's max workers" do
      assert_nothing_raised{ subject.max_workers 2 }
      assert_equal 2, subject.max_workers
    end

    should "allow setting both it's min and max workers with #workers" do
      assert_nothing_raised{ subject.workers 3 }
      assert_equal 3, subject.min_workers
      assert_equal 3, subject.max_workers
    end

    should "allow reading/writing the configuration's wait timeout" do
      assert_nothing_raised{ subject.wait_timeout 1 }
      assert_equal 1, subject.wait_timeout
    end

    should "allow reading/writing the configuration's shutdown timeout" do
      assert_nothing_raised{ subject.shutdown_timeout 15 }
      assert_equal 15, subject.shutdown_timeout
    end

  end

end
