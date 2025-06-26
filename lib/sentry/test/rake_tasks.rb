# frozen_string_literal: true

require "rake/clean"
require "rspec/core/rake_task"

module Sentry
  module Test
    module RakeTasks
      extend Rake::DSL

      def self.define_spec_tasks(options = {})
        opts = {
          isolated_specs_pattern: "spec/isolated/**/*_spec.rb",
          spec_pattern: nil,
          spec_exclude_pattern: nil,
          spec_rspec_opts: nil,
          isolated_rspec_opts: nil
        }.merge(options)

        RSpec::Core::RakeTask.new(:spec).tap do |task|
          task.pattern = opts[:spec_pattern] if opts[:spec_pattern]
          task.exclude_pattern = opts[:spec_exclude_pattern] if opts[:spec_exclude_pattern]
          task.rspec_opts = opts[:spec_rspec_opts] if opts[:spec_rspec_opts]
        end

        namespace :spec do
          RSpec::Core::RakeTask.new(:isolated).tap do |task|
            task.pattern = opts[:isolated_specs_pattern]
            task.rspec_opts = opts[:isolated_rspec_opts] if opts[:isolated_rspec_opts]
          end
        end
      end

      # Define versioned specs task (sentry-rails specific)
      def self.define_versioned_specs_task(options = {})
        opts = {
          rspec_opts: "--order rand"
        }.merge(options)

        namespace :spec do
          RSpec::Core::RakeTask.new(:versioned).tap do |task|
            ruby_ver_dir = RUBY_VERSION.split(".")[0..1].join(".")
            matching_dir = Dir["spec/versioned/*"].detect { |dir| File.basename(dir) <= ruby_ver_dir }

            unless matching_dir
              puts "No versioned specs found for ruby #{RUBY_VERSION}"
              exit 0
            end

            puts "Running versioned specs from #{matching_dir} for ruby #{RUBY_VERSION}"

            task.rspec_opts = opts[:rspec_opts]
            task.pattern = "#{matching_dir}/**/*_spec.rb"
          end
        end
      end
    end
  end
end
