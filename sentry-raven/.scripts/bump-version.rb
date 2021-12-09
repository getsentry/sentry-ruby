file_name = "lib/raven/version.rb"

text = File.read(file_name)
new_contents = text.gsub(/VERSION = ".*"/, "VERSION = \"#{ARGV[1]}\"")
File.open(file_name, "w") {|file| file.puts new_contents }
