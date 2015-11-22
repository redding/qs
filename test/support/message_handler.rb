require 'qs/message_handler'
require 'qs/test_runner'

# manually define some test helpers since we don't provide helpers for
# general message handlers as the user facing helpers are the job/event ones

module Qs::MessageHandler

  module TestHelpers

    def test_runner(handler_class, args = nil)
      Qs::TestRunner.new(handler_class, args)
    end

  end

end
