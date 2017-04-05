require 'qs/version'
require 'qs/client'
require 'qs/daemon'
require 'qs/dispatcher_queue'
require 'qs/event_handler'
require 'qs/job_handler'
require 'qs/queue'

module Qs

  def self.config; @config ||= Config.new; end
  def self.configure(&block)
    block.call(self.config)
  end

  def self.init
    self.config.validate!

    @dispatcher_queue ||= DispatcherQueue.new({
      :queue_class            => self.config.dispatcher_queue_class,
      :queue_name             => self.config.dispatcher_queue_name,
      :job_name               => self.config.dispatcher_job_name,
      :job_handler_class_name => self.config.dispatcher_job_handler_class_name
    })

    @encoder ||= self.config.encoder
    @decoder ||= self.config.decoder
    @client  ||= Client.new(self.redis_connect_hash)
    @redis   ||= @client.redis
    true
  end

  def self.reset!
    @config           = nil
    @dispatcher_queue = nil
    @encoder          = nil
    @decoder          = nil
    @client           = nil
    @redis            = nil
    true
  end

  def self.enqueue(queue, job_name, params = nil)
    self.client.enqueue(queue, job_name, params)
  end

  def self.publish(channel, name, params = nil)
    self.client.publish(channel, name, params)
  end

  def self.publish_as(publisher, channel, name, params = nil)
    self.client.publish_as(publisher, channel, name, params)
  end

  def self.push(queue_name, payload)
    self.client.push(queue_name, payload)
  end

  def self.encode(payload)
    @encoder.call(payload)
  end

  def self.decode(encoded_payload)
    @decoder.call(encoded_payload)
  end

  def self.sync_subscriptions(queue)
    self.client.sync_subscriptions(queue)
  end

  def self.clear_subscriptions(queue)
    self.client.clear_subscriptions(queue)
  end

  def self.event_subscribers(event)
    self.client.event_subscribers(event)
  end

  def self.client
    @client || NullClient.new
  end

  def self.redis
    @redis
  end

  def self.redis_connect_hash
    self.config.redis_connect_hash
  end

  def self.dispatcher_queue
    @dispatcher_queue
  end

  def self.dispatcher_job_name
    self.config.dispatcher_job_name
  end

  def self.event_publisher
    self.config.event_publisher
  end

  def self.published_events
    self.dispatcher_queue.published_events
  end

  class Config

    DEFAULT_ENCODER = proc{ |payload|         ::JSON.dump(payload)         }
    DEFAULT_DECODER = proc{ |encoded_payload| ::JSON.load(encoded_payload) }

    DEFAULT_DISPATCHER_QUEUE_CLASS            = Queue
    DEFAULT_DISPATCHER_QUEUE_NAME             = 'dispatcher'.freeze
    DEFAULT_DISPATCHER_JOB_NAME               = 'run_dispatch_job'.freeze
    DEFAULT_DISPATCHER_JOB_HANDLER_CLASS_NAME = DispatcherQueue::RunDispatchJob.to_s.freeze

    DEFAULT_REDIS_IP      = '127.0.0.1'.freeze
    DEFAULT_REDIS_PORT    = 6379.freeze
    DEFAULT_REDIS_DB      = 0.freeze
    DEFAULT_REDIS_NS      = 'qs'.freeze
    DEFAULT_REDIS_DRIVER  = 'ruby'.freeze
    DEFAULT_REDIS_TIMEOUT = 1.freeze
    DEFAULT_REDIS_SIZE    = 4.freeze

    attr_accessor :encoder, :decoder, :timeout, :event_publisher
    attr_accessor :dispatcher_queue_class, :dispatcher_queue_name
    attr_accessor :dispatcher_job_name, :dispatcher_job_handler_class_name
    attr_accessor :redis_ip, :redis_port, :redis_db, :redis_ns
    attr_accessor :redis_driver, :redis_timeout, :redis_size, :redis_url

    def initialize
      @encoder         = DEFAULT_ENCODER
      @decoder         = DEFAULT_DECODER
      @timeout         = nil
      @event_publisher = nil

      @dispatcher_queue_class            = DEFAULT_DISPATCHER_QUEUE_CLASS
      @dispatcher_queue_name             = DEFAULT_DISPATCHER_QUEUE_NAME
      @dispatcher_job_name               = DEFAULT_DISPATCHER_JOB_NAME
      @dispatcher_job_handler_class_name = DEFAULT_DISPATCHER_JOB_HANDLER_CLASS_NAME

      @redis_ip      = DEFAULT_REDIS_IP
      @redis_port    = DEFAULT_REDIS_PORT
      @redis_db      = DEFAULT_REDIS_DB
      @redis_ns      = DEFAULT_REDIS_NS
      @redis_driver  = DEFAULT_REDIS_DRIVER
      @redis_timeout = DEFAULT_REDIS_TIMEOUT
      @redis_size    = DEFAULT_REDIS_SIZE
      @redis_url     = nil

      @valid = nil
    end

    # the keys here should be compatible with HellaRedis connection configs
    # https://github.com/redding/hella-redis#usage
    def redis_connect_hash
      { :ip       => self.redis_ip,
        :port     => self.redis_port,
        :db       => self.redis_db,
        :redis_ns => self.redis_ns,
        :driver   => self.redis_driver,
        :timeout  => self.redis_timeout,
        :size     => self.redis_size,
        :url      => self.redis_url
      }
    end

    def valid?
      !!@valid
    end

    def validate!
      return @valid if !@valid.nil? # only need to run this once per config

      # set the `redis_url`
      self.redis_url ||= RedisUrl.new(self.redis_ip, self.redis_port, self.redis_db)

      @valid = true
    end

  end

  module RedisUrl

    def self.new(ip, port, db)
      return if ip.to_s.empty? || port.to_s.empty? || db.to_s.empty?
      "redis://#{ip}:#{port}/#{db}"
    end

  end

  class NullClient
    def initialize
      @error = UninitializedError.new("Qs hasn't been initialized")
    end

    def enqueue(*args);             raise @error; end
    def publish(*args);             raise @error; end
    def publish_as(*args);          raise @error; end
    def push(*args);                raise @error; end
    def sync_subscriptions(*args);  raise @error; end
    def clear_subscriptions(*args); raise @error; end
    def event_subscribers(*args);   raise @error; end
  end

  UninitializedError = Class.new(RuntimeError)
  TimeoutError       = Class.new(RuntimeError)

end
