require 'assert'
require 'qs/worker'

require 'dat-worker-pool/worker'
require 'much-plugin'
require 'qs/daemon'
require 'qs/daemon_data'
require 'qs/logger'
require 'qs/queue_item'
require 'test/support/client_spy'

module Qs::Worker

  class UnitTests < Assert::Context
    include DatWorkerPool::Worker::TestHelpers

    desc "Qs::Worker"
    setup do
      @worker_class = Class.new{ include Qs::Worker }
    end
    subject{ @worker_class }

    should "use much-plugin" do
      assert_includes MuchPlugin, Qs::Worker
    end

    should "be a dat-worker-pool worker" do
      assert_includes DatWorkerPool::Worker, subject
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @ph_spy = nil
      Assert.stub(Qs::PayloadHandler, :new) do |*args|
        @ph_spy = PayloadHandlerSpy.new(*args)
      end

      @daemon_data      = Qs::DaemonData.new
      @client_spy       = ClientSpy.new
      @worker_available = Qs::Daemon::WorkerAvailable.new
      @queue_item       = Qs::QueueItem.new(Factory.string, Factory.string)

      @worker_params = {
        :qs_daemon_data      => @daemon_data,
        :qs_client           => @client_spy,
        :qs_worker_available => @worker_available,
        :qs_logger           => Qs::NullLogger.new
      }
      @runner = test_runner(@worker_class, :params => @worker_params)
    end
    subject{ @runner }

    should "build and run a payload handler when it processes a queue item" do
      subject.work(@queue_item)

      assert_not_nil @ph_spy
      assert_equal @daemon_data, @ph_spy.daemon_data
      assert_equal @queue_item,  @ph_spy.queue_item
      assert_true @ph_spy.run_called
    end

    should "signal that a worker is available when it becomes available" do
      signal_called = false
      Assert.stub(@worker_available, :signal){ signal_called = true }

      subject.make_available
      assert_true signal_called
    end

    should "requeue a queue item if an error occurs before its started" do
      exception = Factory.exception
      @queue_item.started = false
      subject.error(exception, @queue_item)

      call = @client_spy.calls.last
      assert_equal :prepend, call.command
      assert_equal @queue_item.queue_redis_key, call.args.first
      assert_equal @queue_item.encoded_payload, call.args.last
    end

    should "not requeue a queue item if an error occurs after its started" do
      exception = Factory.exception
      @queue_item.started = true
      subject.error(exception, @queue_item)

      assert_empty @client_spy.calls
    end

    should "do nothing if not passed a queue item" do
      assert_nothing_raised{ subject.error(Factory.exception) }
      assert_empty @client_spy.calls
    end

  end

  class PayloadHandlerSpy
    attr_reader :daemon_data, :queue_item, :run_called

    def initialize(daemon_data, queue_item)
      @daemon_data = daemon_data
      @queue_item  = queue_item
      @run_called  = false
    end

    def run
      @run_called = true
    end
  end

end
