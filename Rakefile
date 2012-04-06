SUBPROJECTS = Dir['*'].select{|f| File::directory? f}

desc "Run the rspec tests"
task :spec do
  SUBPROJECTS.each do |name|
    Dir.chdir(name) { sh "rake spec" }
  end
end

task :default => :spec
