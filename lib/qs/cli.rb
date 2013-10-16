require 'qs/daemon'
require 'qs/process'
require 'qs/version'

module Qs

  class CLI

    def self.run(*args)
      self.new.run(*args)
    end

    def initialize(kernel = nil)
      @kernel = kernel || Kernel
      @cli = CLIRB.new
    end

    def run(*args)
      run!(*args)
      @kernel.exit 0
    rescue CLIRB::HelpExit
      @kernel.puts help
      @kernel.exit 0
    rescue CLIRB::VersionExit
      @kernel.puts Qs::VERSION
      @kernel.exit 0
    rescue Qs::Process::InvalidError, Qs::Config::InvalidError,
           CLIRB::Error => exception
      @kernel.puts "#{exception.message}\n\n"
      @kernel.puts help
      @kernel.exit 1
    rescue Exception => exception
      @kernel.puts "#{exception.class}: #{exception.message}"
      @kernel.puts exception.backtrace.join("\n") if ENV['DEBUG']
      @kernel.exit 1
    end

    def help
      "Usage: qs <config file> <command> <options> \n" \
      "Commands: run, start, stop, restart \n" \
      "#{@cli}"
    end

    private

    def run!(*args)
      @cli.parse!(*args)
      command          = @cli.args.pop || 'run'
      config_file_path = @cli.args.pop || 'config.qs'
      daemon = Qs::Config.new(config_file_path).daemon
      Qs::Process.call(command, daemon)
    end

  end

  class Config

    # The `Config` evaluates the file and creates a proc using it's contents.
    # This is a trick borrowed from Rack. This is essentially converting a file
    # into a proc and then instance eval'ing it. This has a couple benefits and
    # produces a less confusing outcome:
    # * The obvious benefit is the file is evaluated in the context of this
    #   `Config`. This allows the file to call `run`, setting the Qs daemon to
    #   be run.
    # * The other benefit is that the file's contents behave like they were a
    #   proc defined by the user. Instance eval'ing the file directly, makes any
    #   constants defined in it namespaced by the instance of the config, which
    #   is very confusing. Thus, the proc is created and eval'd in the
    #   `TOPLEVEL_BINDING`, which defines the constants correctly.

    attr_reader :daemon

    def initialize(file_path)
      @file_path = build_file_path(file_path)
      @daemon    = nil
      build_proc = eval("proc{ #{File.read(@file_path)} }", TOPLEVEL_BINDING, @file_path, 0)
      self.instance_eval(&build_proc)
      validate!
    end

    def run(daemon)
      @daemon = daemon
    end

    def validate!
      if !@daemon.kind_of?(Qs::Daemon)
        raise NoDaemonError.new(@daemon, @file_path)
      end
    end

    private

    def build_file_path(path)
      full_path = File.expand_path(path)
      raise NoConfigFileError.new(full_path) unless File.exists?(full_path)
      full_path
    rescue NoConfigFileError
      full_path_with_qs = "#{full_path}.qs"
      raise unless File.exists?(full_path_with_qs)
      full_path_with_qs
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

  class CLIRB  # Version 1.0.0, https://github.com/redding/cli.rb
    Error    = Class.new(RuntimeError);
    HelpExit = Class.new(RuntimeError); VersionExit = Class.new(RuntimeError)
    attr_reader :argv, :args, :opts, :data

    def initialize(&block)
      @options = []; instance_eval(&block) if block
      require 'optparse'
      @data, @args, @opts = [], [], {}; @parser = OptionParser.new do |p|
        p.banner = ''; @options.each do |o|
          @opts[o.name] = o.value; p.on(*o.parser_args){ |v| @opts[o.name] = v }
        end
        p.on_tail('--version', ''){ |v| raise VersionExit, v.to_s }
        p.on_tail('--help',    ''){ |v| raise HelpExit,    v.to_s }
      end
    end

    def option(*args); @options << Option.new(*args); end
    def parse!(argv)
      @args = (argv || []).dup.tap do |args_list|
        begin; @parser.parse!(args_list)
        rescue OptionParser::ParseError => err; raise Error, err.message; end
      end; @data = @args + [@opts]
    end
    def to_s; @parser.to_s; end
    def inspect
      "#<#{self.class}:#{'0x0%x' % (object_id << 1)} @data=#{@data.inspect}>"
    end

    class Option
      attr_reader :name, :opt_name, :desc, :abbrev, :value, :klass, :parser_args

      def initialize(name, *args)
        settings, @desc = args.last.kind_of?(::Hash) ? args.pop : {}, args.pop || ''
        @name, @opt_name, @abbrev = parse_name_values(name, settings[:abbrev])
        @value, @klass = gvalinfo(settings[:value])
        @parser_args = if [TrueClass, FalseClass, NilClass].include?(@klass)
          ["-#{@abbrev}", "--[no-]#{@opt_name}", @desc]
        else
          ["-#{@abbrev}", "--#{@opt_name} #{@opt_name.upcase}", @klass, @desc]
        end
      end

      private

      def parse_name_values(name, custom_abbrev)
        [ (processed_name = name.to_s.strip.downcase), processed_name.gsub('_', '-'),
          custom_abbrev || processed_name.gsub(/[^a-z]/, '').chars.first || 'a'
        ]
      end
      def gvalinfo(v); v.kind_of?(Class) ? [nil,gklass(v)] : [v,gklass(v.class)]; end
      def gklass(k); k == Fixnum ? Integer : k; end
    end
  end

end
