require 'qs'
require 'qs/config_file'
require 'qs/tmp_process'
require 'qs/process_signal'
require 'qs/version'

module Qs

  class CLI

    def self.run(args)
      self.new.run(*args)
    end

    def initialize(kernel = nil)
      @kernel = kernel || Kernel
      @cli = CLIRB.new
    end

    def run(*args)
      begin
        run!(*args)
      rescue CLIRB::HelpExit
        @kernel.puts help
      rescue CLIRB::VersionExit
        @kernel.puts Qs::VERSION
      rescue CLIRB::Error, Qs::ConfigFile::InvalidError => exception
        @kernel.puts "#{exception.message}\n\n"
        @kernel.puts help
        @kernel.exit 1
      rescue StandardError => exception
        @kernel.puts "#{exception.class}: #{exception.message}"
        @kernel.puts exception.backtrace.join("\n")
        @kernel.exit 1
      end
      @kernel.exit 0
    end

    private

    def run!(*args)
      @cli.parse!(args)
      config_file_path, command = @cli.args
      config_file_path ||= 'config.qs'
      command ||= 'run'
      daemon = Qs::ConfigFile.new(config_file_path).daemon
      case(command)
      when 'run'
        Qs::TmpProcess.new(daemon, :daemonize => false).run
      when 'start'
        Qs::TmpProcess.new(daemon, :daemonize => true).run
      when 'stop'
        Qs::ProcessSignal.new(daemon, 'TERM').send
      when 'restart'
        Qs::ProcessSignal.new(daemon, 'USR2').send
      else
        raise CLIRB::Error, "#{command.inspect} is not a valid command"
      end
    end

    def help
      "Usage: qs [CONFIG_FILE] [COMMAND]\n\n" \
      "Commands: run, start, stop, restart\n" \
      "Options: #{@cli}"
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
