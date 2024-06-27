# frozen_string_literal: true

require "optparse"

module Megatest
  class CLI
    class << self
      def run!
        exit(new($PROGRAM_NAME, $stdout, $stderr, ARGV).run)
      end
    end

    undef_method :puts, :print # Should only use @out.puts or @err.puts

    def initialize(program_name, out, err, argv)
      @program_name = program_name
      @out = out
      @err = err
      @argv = argv.dup
      @processes = nil
    end

    def run
      parser.parse!(@argv)

      run_tests
    end

    def run_tests
      Megatest.load_suites(@argv)

      test_cases = Megatest.registry.test_cases
      test_cases.sort!
      test_cases.shuffle!(random: Megatest.seed)

      queue = Queue.new(test_cases)
      executor.run(queue, default_reporters)
      queue.success? ? 0 : 1
    end

    private

    def default_reporters
      [
        SimpleReporter.new(@out),
      ]
    end

    def executor
      if @processes
        require "megatest/multi_process"
        MultiProcess::Executor.new(@processes)
      else
        Executor.new
      end
    end

    def parser
      @parser ||= OptionParser.new do |opts|
        opts.banner = <<~HELP
          Usage: #{@program_name} [SUBCOMMAND] [ARGS]"

          SUBCOMMANDS

          GLOBAL OPTIONS
        HELP

        opts.separator ""

        opts.on("--seed=SEED", Integer, "The seed used to define run order") do |seed|
          Megatest.seed = Random.new(seed)
        end

        opts.on("-j", "--jobs=JOBS", Integer, "Number of processes to use") do |jobs|
          @processes = jobs
        end
      end
    end
  end
end
