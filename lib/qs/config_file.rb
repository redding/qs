require 'qs/daemon'

module Qs

  class ConfigFile

    attr_reader :daemon

    def initialize(file_path)
      @file_path = build_file_path(file_path)
      @daemon = nil
      evaluate_file(@file_path)
      validate!
    end

    def run(daemon)
      @daemon = daemon
    end

    private

    def validate!
      if !@daemon.kind_of?(Qs::Daemon)
        raise NoDaemonError.new(@daemon, @file_path)
      end
    end

    def build_file_path(path)
      full_path = File.expand_path(path)
      raise NoConfigFileError.new(full_path) unless File.exists?(full_path)
      full_path
    rescue NoConfigFileError
      full_path_with_sanford = "#{full_path}.qs"
      raise unless File.exists?(full_path_with_sanford)
      full_path_with_sanford
    end

    # This evaluates the file and creates a proc using it's contents. This is
    # a trick borrowed from Rack. It is essentially converting a file into a
    # proc and then instance eval'ing it. This has a couple benefits:
    # * The obvious benefit is the file is evaluated in the context of this
    #   class. This allows the file to call `run`, setting the daemon that
    #   will be used.
    # * The other benefit is that the file's contents behave like they were a
    #   proc defined by the user. Instance eval'ing the file directly, makes
    #   any constants (modules/classes) defined in it namespaced by the
    #   instance of the config (not namespaced by `Qs::ConfigFile`,
    #   they are actually namespaced by an instance of this class, its like
    #   accessing it via `ConfigFile.new::MyDaemon`), which is very confusing.
    #   Thus, the proc is created and eval'd using the `TOPLEVEL_BINDING`,
    #   which defines the constants at the top-level, as would be expected.
    def evaluate_file(file_path)
      config_file_code = "proc{ #{File.read(file_path)} }"
      config_file_proc = eval(config_file_code, TOPLEVEL_BINDING, file_path, 0)
      self.instance_eval(&config_file_proc)
    end

    InvalidError = Class.new(StandardError)

    class NoConfigFileError < InvalidError
      def initialize(path)
        super "A configuration file couldn't be found at: #{path.to_s.inspect}"
      end
    end

    class NoDaemonError < InvalidError
      def initialize(daemon, path)
        prefix = "Configuration file #{path.to_s.inspect}"
        if daemon
          super "#{prefix} called `run` without a Qs::Daemon"
        else
          super "#{prefix} didn't call `run` with a Qs::Daemon"
        end
      end
    end

  end

end
