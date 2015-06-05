require 'assert'
require 'qs/dispatcher_queue'

module Qs::DispatcherQueue

  class UnitTests < Assert::Context
    desc "Qs::DispatcherQueue"
    subject{ Qs::DispatcherQueue }

    should have_imeths :new

    should "build a dispatcher queue" do
      options = {
        :queue_class            => Class.new(Qs::Queue),
        :queue_name             => Factory.string,
        :job_name               => Factory.string,
        :job_handler_class_name => Factory.string
      }
      dispatcher_queue = subject.new(options)
      assert_instance_of options[:queue_class], dispatcher_queue
      assert_equal options[:queue_name], dispatcher_queue.name

      route = dispatcher_queue.routes.last
      assert_instance_of Qs::Route, route
      exp = Qs::Message::RouteId.new(Qs::Job::PAYLOAD_TYPE, options[:job_name])
      assert_equal exp, route.id
      assert_equal options[:job_handler_class_name], route.handler_class_name
    end

  end

  class RunDispatchJobTests < UnitTests
    desc "RunDispatchJob"
    subject{ RunDispatchJob }

    should "be a dispatch job handler" do
      assert_includes Qs::DispatchJobHandler, subject
    end

  end

end
