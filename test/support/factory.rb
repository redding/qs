require 'assert/factory'
require 'qs/dispatch_job'
require 'qs/error_handler'
require 'qs/job'
require 'qs/event'

module Factory
  extend Assert::Factory

  def self.exception(klass = nil, message = nil)
    klass ||= StandardError
    message ||= Factory.text
    exception = nil
    begin; raise(klass, message); rescue klass => exception; end
    exception.set_backtrace(nil) if Factory.boolean
    exception
  end

  def self.qs_std_error(message = nil)
    self.exception(Qs::ErrorHandler::STANDARD_ERROR_CLASSES.sample, message)
  end

  def self.message(params = nil)
    self.send([:job, :event].sample, params)
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
