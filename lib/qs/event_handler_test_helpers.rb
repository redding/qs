require 'qs/job_test_runner'

module Qs::EventHandler

  module TestHelpers

    def test_runner(handler_class, args = nil)
      Qs::EventTestRunner.new(handler_class, args)
    end

    def test_handler(handler_class, args = nil)
      test_runner(handler_class, args).handler
    end

  end

end
