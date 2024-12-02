# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::StacktraceInterface::Frame do
  describe "#initialize" do
    let(:configuration) { Sentry::Configuration.new }
    let(:raw_lines) do
      [
        "#{Dir.home}/.rvm/gems/activerecord/base.rb:10:in `save'",
        "#{configuration.project_root}/app/models/post.rb:5:in `save_user'"
      ]
    end
    let(:lines) do
      Sentry::Backtrace.parse(raw_lines, configuration.project_root, configuration.app_dirs_pattern).lines
    end

    it "initializes a Frame with the correct info from the given Backtrace::Line object" do
      first_frame = Sentry::StacktraceInterface::Frame.new(configuration.project_root, lines.first)

      expect(first_frame.filename).to match(/base.rb/)
      expect(first_frame.in_app).to eq(false)
      expect(first_frame.function).to eq("save")
      expect(first_frame.lineno).to eq(10)

      second_frame = Sentry::StacktraceInterface::Frame.new(configuration.project_root, lines.last)

      expect(second_frame.filename).to match(/post.rb/)
      expect(second_frame.in_app).to eq(true)
      expect(second_frame.function).to eq("save_user")
      expect(second_frame.lineno).to eq(5)
    end

    it "does not strip load path when strip_backtrace_load_path is false" do
      first_frame = Sentry::StacktraceInterface::Frame.new(configuration.project_root, lines.first, false)
      expect(first_frame.filename).to eq(first_frame.abs_path)
      expect(first_frame.filename).to eq(raw_lines.first.split(':').first)

      second_frame = Sentry::StacktraceInterface::Frame.new(configuration.project_root, lines.last, false)
      expect(second_frame.filename).to eq(second_frame.abs_path)
      expect(second_frame.filename).to eq(raw_lines.last.split(':').first)
    end
  end
end
