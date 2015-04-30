module Qs

  class IOPipe

    NULL = File.open('/dev/null', 'w')
    NUMBER_OF_BYTES = 1

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
      @reader.read_nonblock(NUMBER_OF_BYTES)
    end

    def write(value)
      @writer.write_nonblock(value[0, NUMBER_OF_BYTES])
    end

    def wait
      ::IO.select([@reader])
      self
    end

  end

end
