require "spec_helper"

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
    Regexp.new("^(#{project_root}/)?#{Sentry::Backtrace::APP_DIRS_PATTERN}")
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
end
