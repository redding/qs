require 'qs/event_handler'

module MyTestApp; end
module MyTestApp::EventHandlers

  class TestEvent
    include Qs::EventHandler
    attr_reader :init_was_called, :run_was_called

    def init!; @init_was_called = true; end
    def run!;  @run_was_called  = true; end

  end

  # TODO: TrackRunsTriggered
  # class TrackRunsTriggered
  #   include Qs::EventHandler

  #   def init!
  #     @redis = Qs::RedisConnection.new
  #   end

  #   def run!
  #     @redis.set('track_runs_triggered', (self.args['value'] || Time.now))
  #   end

  # end

end
