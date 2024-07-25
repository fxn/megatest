# frozen_string_literal: true

module Megatest
  class Runner
    def initialize(config)
      @config = config
    end

    def execute(test_case)
      if test_case.tag(:isolated)
        read, write = IO.pipe.each(&:binmode)
        pid = Process.fork do
          read.close
          result = run(test_case)
          Marshal.dump(result, write)
          write.close
          # We don't want to run at_exit hooks the app may have
          # installed.
          Process.exit!(0)
        end
        write.close
        result = begin
          Marshal.load(read)
        rescue EOFError
          TestCaseResult.new(test_case).lost
        end
        Process.wait(pid)
        result
      else
        run(test_case)
      end
    end

    def run(test_case)
      result = TestCaseResult.new(test_case)
      runtime = Runtime.new(@config, test_case, result)
      instance = test_case.klass.new(runtime)

      # We always reset the seed before running any test as to have the most consistent
      # result as possible, especially on retries.
      Random.srand(@config.seed)

      result.record_time do
        ran = false
        failed = false
        recursive_callbacks(test_case.around_callbacks) do
          ran = true
          return result if runtime.record_failures { instance.before_setup }

          test_case.each_setup_callback do |callback|
            failed ||= runtime.record_failures(downlevel: 2) { instance.instance_exec(&callback) }
          end
          failed ||= runtime.record_failures { instance.setup }
          failed ||= runtime.record_failures { instance.after_setup }

          failed ||= test_case.execute(runtime, instance)

          result.ensure_assertions unless @config.minitest_compatibility
        ensure
          runtime.record_failures do
            instance.before_teardown
          end
          test_case.each_teardown_callback do |callback|
            runtime.record_failures(downlevel: 2) do
              instance.instance_exec(&callback)
            end
          end
          runtime.record_failures do
            instance.teardown
          end
          runtime.record_failures do
            instance.after_teardown
          end
        end

        result.did_not_run unless ran
      end
    end

    def recursive_callbacks(callbacks, &block)
      if callback = callbacks.pop
        callback.call(-> { recursive_callbacks(callbacks, &block) })
      else
        yield
      end
    end
  end
end
