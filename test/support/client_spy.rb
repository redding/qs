require 'qs/client'

class ClientSpy < Qs::TestClient
  attr_reader :calls

  def initialize(redis_config = nil)
    super(redis_config || {})
    @calls = []
    @list  = []
    @mutex = Mutex.new
    @cv    = ConditionVariable.new
  end

  def block_dequeue(*args)
    @calls << Call.new(:block_dequeue, args)
    if @list.empty?
      @mutex.synchronize{ @cv.wait(@mutex) }
    end
    @list.shift
  end

  def append(*args)
    @calls << Call.new(:append, args)
    @list  << args
    @cv.signal
  end

  def prepend(*args)
    @calls << Call.new(:prepend, args)
    @list  << args
    @cv.signal
  end

  def clear(*args)
    @calls << Call.new(:clear, args)
  end

  def ping
    @calls << Call.new(:ping)
  end

  Call = Struct.new(:command, :args)
end
