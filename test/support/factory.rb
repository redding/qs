require 'assert/factory'
require 'qs/job'
require 'qs/event'

module Factory
  extend Assert::Factory

  def self.exception(klass = nil, message = nil)
    klass ||= StandardError
    message ||= Factory.text
    exception = nil
    begin; raise(klass, message); rescue StandardError => exception; end
    exception
  end

  def self.job(params = nil)
    name       = Factory.string
    params     = { Factory.string => Factory.string }
    created_at = Factory.time
    Qs::Job.new(name, params, created_at)
  end

  def self.event_job(params = nil)
    channel      = Factory.string
    event        = Factory.string
    params       = { Factory.string => Factory.string }
    published_at = Factory.time
    Qs::Event.build(channel, event, params, published_at).job
  end

end
