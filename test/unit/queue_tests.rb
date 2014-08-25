require 'assert'
require 'qs/queue'

require 'test/support/factory'

class Qs::Queue

  class UnitTests < Assert::Context
    desc "Qs::Queue"
    setup do
      @queue = Qs::Queue.new do
        name Factory.string
      end
    end
    subject{ @queue }

    should have_readers :routes
    should have_imeths :name, :redis_key, :job_handler_ns, :job

    should "build an empty array for its routes by default" do
      assert_equal [], subject.routes
    end

    should "allow setting its name" do
      name = Factory.string
      subject.name name
      assert_equal name, subject.name
    end

    should "know its redis key" do
      assert_equal "queues:#{subject.name}", subject.redis_key
    end

    should "not have a job handler ns by default" do
      assert_nil subject.job_handler_ns
    end

    should "allow setting its job handler ns" do
      namespace = Factory.string
      subject.job_handler_ns namespace
      assert_equal namespace, subject.job_handler_ns
    end

    should "allow adding routes using `job`" do
      job_name = Factory.string
      handler_name = Factory.string
      subject.job job_name, handler_name

      route = subject.routes.last
      assert_instance_of Qs::Route, route
      assert_equal job_name, route.name
      assert_equal handler_name, route.handler_class_name
    end

    should "use its job handler ns when adding routes" do
      namespace = Factory.string
      subject.job_handler_ns namespace

      job_name = Factory.string
      handler_name = Factory.string
      subject.job job_name, handler_name

      route = subject.routes.last
      expected = "#{namespace}::#{handler_name}"
      assert_equal expected, route.handler_class_name
    end

    should "know its custom inspect" do
      reference = '0x0%x' % (subject.object_id << 1)
      expected = "#<#{subject.class}:#{reference} " \
                   "@name=#{subject.name.inspect} " \
                   "@job_handler_ns=#{subject.job_handler_ns.inspect}>"
      assert_equal expected, subject.inspect
    end

    should "require a name when initialized" do
      assert_raises(InvalidError){ Qs::Queue.new }
    end

  end

end
