class PIDFileSpy

  attr_reader :pid, :write_called, :remove_called

  def initialize(pid)
    @pid = pid
    @write_called = false
    @remove_called = false
  end

  def write
    @write_called = true
  end

  def remove
    @remove_called = true
  end

end
