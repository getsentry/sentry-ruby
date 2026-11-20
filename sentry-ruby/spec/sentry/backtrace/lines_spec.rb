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

    it "converts JRuby .class files to .rb" do
      2.times do
        line = described_class.parse("uri:classloader:/gems/foo/lib/foo.class:7:in `bar'")

        expect(line.file).to eq("/gems/foo/lib/foo.rb")
        expect(line.number).to eq(7)
        expect(line.method).to eq("bar")
      end
    end

    context "parse cache" do
      let(:parse_cache) { described_class.instance_variable_get(:@parse_cache) }

      before { parse_cache.clear }

      it "reuses frozen parsed strings for a repeated line" do
        first = described_class.parse(unparsed_gem_line.dup, in_app_pattern)
        second = described_class.parse(unparsed_gem_line.dup, in_app_pattern)

        expect(second.file).to equal(first.file)
        expect(second.method).to equal(first.method)
        expect(second.file).to be_frozen
        expect(second.method).to be_frozen
        expect(second).not_to equal(first)
      end

      it "computes in_app from the pattern of each call, not the cached one" do
        other_pattern = /sinatra/

        expect(described_class.parse(unparsed_gem_line, in_app_pattern).in_app).to eq(false)
        expect(described_class.parse(unparsed_gem_line, other_pattern).in_app).to eq(true)
        expect(described_class.parse(unparsed_gem_line).in_app).to eq(false)
      end

      it "caches lines that don't match any format" do
        2.times do
          line = described_class.parse("not a backtrace line")

          expect(line.file).to be_nil
          expect(line.number).to eq(0)
        end
        expect(parse_cache.size).to eq(1)
      end

      it "clears itself once it reaches PARSE_CACHE_LIMIT" do
        stub_const("#{described_class}::PARSE_CACHE_LIMIT", 2)

        described_class.parse("a.rb:1:in `a'")
        described_class.parse("b.rb:2:in `b'")
        expect(parse_cache.size).to eq(2)

        line = described_class.parse("c.rb:3:in `c'")
        expect(parse_cache.size).to eq(1)
        expect(line.file).to eq("c.rb")
        expect(line.number).to eq(3)
      end
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
