#!/usr/bin/env ruby

file_names = ['lib/raven/version.rb']

file_names.each do |file_name|
  text = File.read(file_name)
  new_contents = text.gsub(/\d.\d.\d/, ARGV[1])
  File.open(file_name, "w") {|file| file.puts new_contents }
end