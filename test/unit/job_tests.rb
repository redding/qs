require 'assert'
require 'qs/job'

class Qs::Job

  class BaseTests < Assert::Context
    desc "qs::Job"
    setup do
      @job = Qs::Job.new
    end
    subject{ @job }

    should have_imeths :queue_class, :handler_class, :handler_args

    should "default its data" do
      assert_equal '', subject.queue_class
      assert_equal '', subject.handler_class
      assert_equal({}, subject.handler_args)

    end

    should "build from just some handler args" do
      job = Qs::Job.new({'some' => 'data'})

      assert_equal '', job.queue_class
      assert_equal '', job.handler_class
      assert_equal({'some' => 'data'}, job.handler_args)
    end

    should "build from just a handler class and some handler args" do
      job = Qs::Job.new('a_handler', {'some' => 'data'})

      assert_equal '', job.queue_class
      assert_equal 'a_handler', job.handler_class
      assert_equal({'some' => 'data'}, job.handler_args)
    end

    should "build from a queue_class, a handler class, and some handler args" do
      job = Qs::Job.new('a_queue', 'a_handler', {'some' => 'data'})

      assert_equal 'a_queue', job.queue_class
      assert_equal 'a_handler', job.handler_class
      assert_equal({'some' => 'data'}, job.handler_args)
    end

  end

end
