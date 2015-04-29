module Qs

  class IOPipe

    NULL = File.open('/dev/null', 'w')

    attr_reader :reader, :writer

    def initialize
      @reader = NULL
      @writer = NULL
    end

    def setup
      @reader, @writer = ::IO.pipe
    end

    def teardown
      @reader.close unless @reader === NULL
      @writer.close unless @writer === NULL
      @reader = NULL
      @writer = NULL
    end

    def read
      @reader.gets.strip
    end

    def write(value)
      @writer.puts(value)
    end

    def wait
      ::IO.select([@reader])
      self
    end

  end

end
