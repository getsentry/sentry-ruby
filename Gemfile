Dir['*/Gemfile'].each do |gemfile|
  Dir.chdir(File.dirname(gemfile)) do
    eval(IO.read(File.basename(gemfile)))
  end
end
