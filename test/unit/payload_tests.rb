require 'assert'
require 'qs/payload'

module Qs::Payload

  class UnitTests < Assert::Context
    desc "Qs::Payload"
    setup do
      @payload = Qs::Payload
    end
    subject{ @payload }

    should have_imeths :encode, :decode

    should "encode and decode using Oj" do
      object = { Factory.string => Factory.string }
      serialized_object = subject.encode(object)
      assert_equal Oj.dump(object), serialized_object
      assert_equal object, subject.decode(serialized_object)
    end

    should "use Oj's strict mode" do
      assert_raises(TypeError){ subject.encode(:test => Factory.string) }
      assert_raises(TypeError){ subject.encode(Factory.string => Class.new) }

      klass = Class.new
      invalid = Oj.dump(:test => klass)
      expected = { ":test" => { "^c" => klass.inspect } }
      assert_equal expected, subject.decode(invalid)
    end

  end

end
