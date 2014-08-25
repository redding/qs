require 'fileutils'

module Qs

  class PIDFile
    attr_reader :path

    def initialize(path)
      @path = (path || '/dev/null').to_s
    end

    def pid
      pid = File.read(@path).strip
      pid && !pid.empty? ? pid.to_i : raise('no pid in file')
    rescue StandardError => exception
      error = InvalidError.new("A PID couldn't be read from #{@path.inspect}")
      error.set_backtrace(exception.backtrace)
      raise error
    end

    def write
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, 'w'){ |f| f.puts ::Process.pid }
    rescue StandardError => exception
      error = InvalidError.new("Can't write pid to file #{@path.inspect}")
      error.set_backtrace(exception.backtrace)
      raise error
    end

    def remove
      FileUtils.rm_f(@path)
    end

    def to_s
      @path
    end

    InvalidError = Class.new(RuntimeError)

  end

end
