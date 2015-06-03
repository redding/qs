require 'assert/factory'
require 'qs/dispatch_job'
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

  def self.message(params = nil)
    self.send([:job, :event].choice, params)
  end

  def self.job(args = nil)
    args ||= {}
    name = args.delete(:name) || Factory.string
    args[:params]     ||= { Factory.string => Factory.string }
    args[:created_at] ||= Factory.time
    Qs::Job.new(name, args)
  end

  def self.dispatch_job(args = nil)
    args ||= {}
    event_channel = args.delete(:event_channel) || Factory.string
    event_name    = args.delete(:event_name)    || Factory.string
    args[:event_params] ||= { Factory.string => Factory.string }
    args[:created_at]   ||= Factory.time
    Qs::DispatchJob.new(event_channel, event_name, args)
  end

  def self.event(args = nil)
    args ||= {}
    channel = args.delete(:channel) || Factory.string
    name    = args.delete(:name)    || Factory.string
    args[:params]       ||= { Factory.string => Factory.string }
    args[:publisher]    ||= Factory.string
    args[:published_at] ||= Factory.time
    Qs::Event.new(channel, name, args)
  end

end
