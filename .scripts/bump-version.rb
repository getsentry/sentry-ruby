ref_name = `git branch --show-current`
sdk_name_capture_regex = /release-(sentry-\w+)\/.*/

file_name =
  if sdk_name_match = ref_name.match(sdk_name_capture_regex)
    case sdk_name = sdk_name_match[1]
    when "sentry-ruby"
      "lib/sentry/version.rb"
    else
      integration_name = sdk_name.sub("sentry-", "")
      "lib/sentry/#{integration_name}/version.rb"
    end
  else
    # old SDK
    "lib/raven/version.rb"
  end

text = File.read(file_name)
new_contents = text.gsub(/VERSION = ".*"/, "VERSION = \"#{ARGV[1]}\"")
File.open(file_name, "w") {|file| file.puts new_contents }
