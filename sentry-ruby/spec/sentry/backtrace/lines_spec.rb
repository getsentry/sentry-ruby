# frozen_string_literal: true

RSpec.describe Sentry::Backtrace::Line do
  before do
    perform_basic_setup
  end
  let(:unparsed_app_line) do
    "app.rb:12:in `/'"
  end
  let(:unparsed_gem_line) do
    "/PATH_TO_RUBY/gems/2.7.0/gems/sinatra-2.1.0/lib/sinatra/base.rb:1675:in `call'"
  end

  let(:in_app_pattern) do
    project_root = Sentry.configuration.project_root&.to_s
    Regexp.new("^(#{project_root}/)?#{Sentry::Configuration::APP_DIRS_PATTERN}")
  end

  describe ".parse" do
    it "parses app backtrace correctly" do
      line = described_class.parse(unparsed_app_line, in_app_pattern)

      expect(line.file).to eq("app.rb")
      expect(line.number).to eq(12)
      expect(line.method).to eq("/")
      expect(line.in_app_pattern).to eq(in_app_pattern)
      expect(line.module_name).to eq(nil)
      expect(line.in_app).to eq(true)
    end

    it "parses gem backtrace correctly" do
      line = described_class.parse(unparsed_gem_line, in_app_pattern)

      expect(line.file).to eq(
        "/PATH_TO_RUBY/gems/2.7.0/gems/sinatra-2.1.0/lib/sinatra/base.rb"
      )
      expect(line.number).to eq(1675)
      expect(line.method).to eq("call")
      expect(line.in_app_pattern).to eq(in_app_pattern)
      expect(line.module_name).to eq(nil)
      expect(line.in_app).to eq(false)
    end
  end

  describe ".from_source_location", skip: !Thread.respond_to?(:each_caller_location) do
    it "creates a Line from Thread::Backtrace::Location" do
      location = caller_locations.first
      line = described_class.from_source_location(location, in_app_pattern)

      expect(line).to be_a(described_class)
      expect(line.file).to be_a(String)
      expect(line.number).to be_a(Integer)
      expect(line.method).to be_a(String)
      expect(line.in_app_pattern).to eq(in_app_pattern)
    end

    it "extracts file, line number, and method correctly" do
      location = caller_locations.first
      line = described_class.from_source_location(location)

      expect(line.file).to eq(location.absolute_path)
      expect(line.number).to eq(location.lineno)
      expect(line.method).to eq(location.base_label)
    end

    it "extracts module name from label when present", when: { ruby_version?: [:>=, "3.4"] } do
      location = caller_locations.first
      line = described_class.from_source_location(location)

      expect(line.module_name).to be_a(String)
    end

    it "skips module name from label when present", when: { ruby_version?: [:<, "3.4"] } do
      location = caller_locations.first
      line = described_class.from_source_location(location)

      expect(line.module_name).to be(nil)
    end
  end
end
