require 'benchmark'
require 'scmd'
require 'bench/queue'

class BenchRunner

  TIME_MODIFIER = 10 ** 4 # 4 decimal places

  def initialize
    output_file_path = if ENV['OUTPUT_FILE']
      File.expand_path(ENV['OUTPUT_FILE'])
    else
      File.expand_path('../report.txt', __FILE__)
    end
    @output_file = File.open(output_file_path, 'w')

    @number_of_jobs = ENV['NUM_JOBS'] || 10_000
    @job_name       = 'multiply'
    @job_params     = { 'size' => 100_000 }

    @progress_reader, @progress_writer = IO.pipe

    @results = {}

    Qs.init
  end

  def run
    output "Running benchmark report..."
    output("\n", false)

    benchmark_adding_jobs
    benchmark_running_jobs

    size = @results.values.map(&:size).max
    output "Adding #{@number_of_jobs} Jobs Time:  #{@results[:adding_jobs].rjust(size)}s"
    output "Running #{@number_of_jobs} Jobs Time: #{@results[:running_jobs].rjust(size)}s"

    output "\n"
    output "Done running benchmark report"
  end

  private

  def benchmark_adding_jobs
    output "Adding jobs"
    benchmark = Benchmark.measure do
      (1..@number_of_jobs).each do |n|
        BenchQueue.add(@job_name, @job_params)
        output('.', false) if ((n - 1) % 100 == 0)
      end
    end
    @results[:adding_jobs] = round_and_display(benchmark.real)
    output("\n", false)
  end

  def benchmark_running_jobs
    cmd_str = "bundle exec ./bin/qs bench/config.qs"
    cmd = Scmd.new(cmd_str, {
      'BENCH_REPORT'      => 'yes',
      'BENCH_PROGRESS_IO' => @progress_writer.fileno
    })

    output "Running jobs"
    begin
      benchmark = Benchmark.measure do
        cmd.start
        if !cmd.running?
          raise "failed to start qs process: #{cmd_str.inspect}"
        end

        progress = 0
        while progress < @number_of_jobs
          ::IO.select([@progress_reader])
          result = @progress_reader.read_nonblock(1)
          progress += 1
          output(result, false) if ((progress - 1) % 100 == 0)
        end
      end
      @results[:running_jobs] = round_and_display(benchmark.real)
      output("\n", false)
    ensure
      cmd.kill('TERM')
      cmd.wait(5)
    end

    output("\n", false)
  end

  private

  def output(message, puts = true)
    method = puts ? :puts : :print
    self.send(method, message)
    @output_file.send(method, message)
    STDOUT.flush if method == :print
  end

  def round_and_display(time_in_ms)
    display_time(round_time(time_in_ms))
  end

  def round_time(time_in_ms)
    (time_in_ms * TIME_MODIFIER).to_i / TIME_MODIFIER.to_f
  end

  def display_time(time)
    integer, fractional = time.to_s.split('.')
    [ integer, fractional.ljust(4, '0') ].join('.')
  end

end

BenchRunner.new.run
