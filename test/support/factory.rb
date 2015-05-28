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

  def self.job(params = nil)
    params ||= {}
    params[:name]       ||= Factory.string
    params[:params]     ||= { Factory.string => Factory.string }
    params[:created_at] ||= Factory.time
    Qs::Job.new(
      params.delete(:name),
      params.delete(:params),
      params
    )
  end

  def self.dispatch_job(params = nil)
    params ||= {}
    params[:event_channel] ||= Factory.string
    params[:event_name]    ||= Factory.string
    params[:event_params]  ||= { Factory.string => Factory.string }
    params[:created_at]    ||= Factory.time
    Qs::DispatchJob.new(
      params.delete(:event_channel),
      params.delete(:event_name),
      params.delete(:event_params),
      params
    )
  end

  def self.event(params = nil)
    params ||= {}
    params[:channel]      ||= Factory.string
    params[:name]         ||= Factory.string
    params[:params]       ||= { Factory.string => Factory.string }
    params[:publisher]    ||= Factory.string
    params[:published_at] ||= Factory.time
    Qs::Event.new(
      params.delete(:channel),
      params.delete(:name),
      params.delete(:params),
      params
    )
  end

end
