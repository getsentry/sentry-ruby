INTEGRATIONS = %w(sentry-rails sentry-sidekiq sentry-delayed_job sentry-resque sentry-opentelemetry)
GEMS = %w(sentry-ruby) + INTEGRATIONS

def get_version_file_name(gem_name)
  case gem_name
  when "sentry-ruby"
    "lib/sentry/version.rb"
  else
    integration_name = gem_name.sub("sentry-", "")
    "lib/sentry/#{integration_name}/version.rb"
  end
end

def update_version_file(gem_name, version)
  version_file_name = get_version_file_name(gem_name)
  file_name = "#{gem_name}/#{version_file_name}"
  text = File.read(file_name)
  new_contents = text.gsub(/VERSION = ".*"/, "VERSION = \"#{version}\"")
  File.open(file_name, "w") {|file| file.puts new_contents }
end

def update_gemspec_dependency(gem_name, version)
  file_name = "#{gem_name}/#{gem_name}.gemspec"
  text = File.read(file_name)
  new_contents = text.gsub(/spec.add_dependency "sentry-ruby", ".+"/, "spec.add_dependency \"sentry-ruby\", \"~> #{version}\"")
  File.open(file_name, "w") {|file| file.puts new_contents }
end

# when craft runs scripts it inserts version to the 2nd argument
version = ARGV[1]

raise "version is not specified!" if version.nil? || version.empty?

GEMS.each do |gem_name|
  update_version_file(gem_name, version)
end

INTEGRATIONS.each do |gem_name|
  update_gemspec_dependency(gem_name, version)
end
