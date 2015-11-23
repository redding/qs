require 'benchmark'
require 'scmd'
require 'bench/setup'

class BenchRunner

  BUNDLE_EXEC        = "bundle exec --keep-file-descriptors".freeze
  RUN_QS_BENCH_QUEUE = "#{BUNDLE_EXEC} ./bin/qs bench/config.qs".freeze
  RUN_QS_DISPATCHER  = "#{BUNDLE_EXEC} ./bin/qs bench/dispatcher.qs".freeze
  TIME_MODIFIER      = 10 ** 4 # 4 decimal places

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

    @number_of_events = ENV['NUM_EVENTS'] || 10_000
    @event_channel    = 'something'
    @event_name       = 'happened'
    @event_params     = { 'size' => 100_000 }

    @progress_reader, @progress_writer = IO.pipe
    @run_qs_scmd_opts = {
      :env => {
        'BENCH_REPORT'      => 'yes',
        'BENCH_PROGRESS_IO' => @progress_writer.fileno.to_s
      },
      :options => { @progress_writer => @progress_writer }
    }

    @results = {}
  end

  def run
    output "Running benchmark report..."
    output("\n", false)

    Qs.client.clear(BenchQueue.redis_key)
    Qs.client.clear(Qs.dispatcher_queue.redis_key)

    benchmark_enqueueing_jobs
    benchmark_running_jobs

    benchmark_publishing_events
    benchmark_running_events

    size = @results.values.map(&:size).max
    output "\n", false
    output "Enqueueing #{@number_of_jobs} Jobs Time: #{@results[:enqueueing_jobs].rjust(size)}s"
    output "Running #{@number_of_jobs} Jobs Time:    #{@results[:running_jobs].rjust(size)}s"

    output "\n", false
    output "Publishing #{@number_of_events} Events Time: #{@results[:publishing_events].rjust(size)}s"
    output "Running #{@number_of_events} Events Time:    #{@results[:running_events].rjust(size)}s"

    output "\n"
    output "Done running benchmark report"
  end

  private

  def benchmark_enqueueing_jobs
    output "Enqueuing jobs"
    benchmark = Benchmark.measure do
      (1..@number_of_jobs).each do |n|
        BenchQueue.add(@job_name, @job_params)
        output('.', false) if ((n - 1) % 100 == 0)
      end
    end
    @results[:enqueueing_jobs] = round_and_display(benchmark.real)
    output("\n", false)
  end

  def benchmark_running_jobs
    cmd = Scmd.new(RUN_QS_BENCH_QUEUE, @run_qs_scmd_opts)

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
    ensure
      cmd.kill('TERM')
      cmd.wait(5)
    end

    output("\n", false)
  end

  def benchmark_publishing_events
    output "Publishing events"
    benchmark = Benchmark.measure do
      (1..@number_of_events).each do |n|
        Qs.publish(@event_channel, @event_name, @event_params)
        output('.', false) if ((n - 1) % 100 == 0)
      end
    end
    @results[:publishing_events] = round_and_display(benchmark.real)
    output("\n", false)
  end

  def benchmark_running_events
    bench_queue_cmd      = Scmd.new(RUN_QS_BENCH_QUEUE, @run_qs_scmd_opts)
    dispatcher_queue_cmd = Scmd.new(RUN_QS_DISPATCHER, @run_qs_scmd_opts)

    output "Running events"
    begin
      benchmark = Benchmark.measure do
        bench_queue_cmd.start
        if !bench_queue_cmd.running?
          raise "failed to start qs process: #{bench_queue_cmd_str.inspect}"
        end

        dispatcher_queue_cmd.start
        if !dispatcher_queue_cmd.running?
          raise "failed to start qs process: #{dispatcher_queue_cmd_str.inspect}"
        end

        progress = 0
        while progress < @number_of_jobs
          ::IO.select([@progress_reader])
          result = @progress_reader.read_nonblock(1)
          progress += 1
          output(result, false) if ((progress - 1) % 100 == 0)
        end
      end
      @results[:running_events] = round_and_display(benchmark.real)
    ensure
      dispatcher_queue_cmd.kill('TERM')
      bench_queue_cmd.kill('TERM')
      dispatcher_queue_cmd.wait(5)
      bench_queue_cmd.wait(5)
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
