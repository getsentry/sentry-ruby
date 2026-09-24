# frozen_string_literal: true

module Test
  module ForkHelper
    TIMEOUT = 1

    def capture_in_separate_process(exit_code: 0)
      reader, writer = IO.pipe
      pid = fork do
        reader.close
        yield(writer)
        exit(exit_code)
      end

      writer.close
      output = read_from_child(reader)
      wait_for_child(pid)
      output
    ensure
      reader&.close
      writer&.close
      terminate_child(pid)
    end

    private

    def read_from_child(reader)
      output = +""
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT

      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise "child did not respond" if remaining <= 0
        raise "child did not respond" unless IO.select([reader], nil, nil, remaining)

        begin
          output << reader.read_nonblock(4096)
        rescue IO::WaitReadable
          next
        rescue EOFError
          return output
        end
      end
    end

    def wait_for_child(pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT

      loop do
        return if Process.waitpid(pid, Process::WNOHANG)
        raise "child did not exit" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.01
      end
    end

    def terminate_child(pid)
      return unless pid

      begin
        return if Process.waitpid(pid, Process::WNOHANG)

        Process.kill("KILL", pid)
        Process.wait(pid)
      rescue Errno::ECHILD, Errno::ESRCH
      end
    end
  end
end
