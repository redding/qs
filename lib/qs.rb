require 'logger'
require 'stringio'
require 'ns-options'
require 'qs/version'

module Qs

  def self.config; Config; end
  def self.configure(&block); Config.define(&block); end

  def self.init
    # TODO: lib init code goes here...
  end

  class Config
    include NsOptions::Proxy

    option :timeout, Fixnum, :default => proc { Qs::Config.default_timeout }
    option :logger,          :default => proc { Qs::Config.null_logger }

    def self.default_timeout
      300 # seconds (5 mins)
    end

    def self.null_logger
      @null_logger ||= Logger.new(StringIO.new)
    end

  end

end
