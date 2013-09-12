require 'logger'

module Qs; end
class Qs::Queue

  # This is temporary, just defining what a daemon needs from a queue
  attr_accessor :name, :logger, :mappings

  def initialize
    @logger ||= Logger.new(File.open("/dev/null", 'w'))
    @mappings = []
  end

end
