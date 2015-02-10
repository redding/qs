class RunnerSpy

  attr_reader :handler_class, :args, :handler
  attr_reader :run_called

  def initialize(handler_class, args = nil)
    @handler_class = handler_class
    @args          = args
    @handler       = Factory.string
    @run_called    = false
  end

  def run
    @run_called = true
  end

end
