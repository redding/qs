module Qs; end
class Qs::Queue

  # This is temporary, just defining what a daemon needs from a queue
  attr_accessor :mappings

  def initialize
    @mappings = []
  end

end
