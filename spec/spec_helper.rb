require 'coveralls'
Coveralls.wear!

def build_exception()
  begin
    1 / 0
  rescue ZeroDivisionError => exception
    return exception
  end
end

def run_rake_task(task)
  cwd = File.dirname(__FILE__)

  rakefile = File.join(cwd, 'support', 'Rakefile')
  tmp_dir  = File.join(cwd, 'tmp')

  FileUtils.mkdir_p(tmp_dir)
  FileUtils.cp rakefile, tmp_dir

  cmd = Dir.chdir(tmp_dir) do
    run("bundle exec rake #{task}")
  end

  FileUtils.rm_rf(tmp_dir)

  cmd
end

def run(command)
  stderr_file = Tempfile.new('rspec')
  stderr_file.close

  cmd_stdout = nil

  mode = {:external_encoding=>"UTF-8"}

  IO.popen("#{command} 2> #{stderr_file.path}", mode) do |io|
    cmd_stdout = io.read
  end

  {
    exit_status: $?.exitstatus,
    stderr: IO.read(stderr_file.path),
    stdout: cmd_stdout
  }
end
