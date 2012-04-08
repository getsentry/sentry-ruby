SUBPROJECTS = Dir['*'].select{|f| File::directory? f}

desc "Run all the bundle installs"
task :bundle do
  SUBPROJECTS.each do |name|
    without = ENV["BUNDLE_WITHOUT"] ? ENV["BUNDLE_WITHOUT"].split(",").map{|s| "--without #{s}"}.join(" ") : ""
    Dir.chdir(name) { sh "bundle install #{without}" }
  end
end

desc "Run the rspec tests"
task :spec do
  SUBPROJECTS.each do |name|
    Dir.chdir(name) { sh "rake spec" }
  end
end

task :default => :spec
