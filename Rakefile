# frozen_string_literal: true

require "rake/clean"
require_relative "lib/sentry/test/rake_tasks"

Sentry::Test::RakeTasks.define_spec_tasks()

# Define E2E test tasks
namespace :spec do
  desc "Run end-to-end tests (requires background services)"
  task :e2e do
    puts "Running E2E tests..."
    puts "Note: Make sure background services are running:"
    puts "  Foreman: foreman start"
    puts "  Docker: cd .devcontainer && docker-compose --profile e2e up -d"

    system("bundle exec rspec spec/features/ --format progress") || exit(1)
  end

  desc "Run E2E tests with Docker Compose (devcontainer setup)"
  task :e2e_docker do
    puts "Starting E2E services with devcontainer Docker Compose and running tests..."

    begin
      # Start services using devcontainer setup
      Dir.chdir('.devcontainer') do
        unless system("docker-compose --profile e2e up -d rails-mini svelte-mini")
          puts "Failed to start E2E services"
          exit(1)
        end
      end

      # Wait for services to be ready
      puts "Waiting for services to be ready..."
      puts "Checking Rails mini app health..."
      unless system("timeout 60 bash -c 'until curl -s http://localhost:5000/health | grep -q \"ok\"; do echo \"Waiting for Rails app...\"; sleep 2; done'")
        puts "Rails mini app failed to become ready"
        Dir.chdir('.devcontainer') { system("docker-compose --profile e2e down") }
        exit(1)
      end
      puts "✅ Rails mini app is ready"

      puts "Checking Svelte mini app health..."
      unless system("timeout 60 bash -c 'until curl -s http://localhost:5001/health | grep -q \"ok\"; do echo \"Waiting for Svelte app...\"; sleep 2; done'")
        puts "Svelte mini app failed to become ready"
        Dir.chdir('.devcontainer') { system("docker-compose --profile e2e down") }
        exit(1)
      end
      puts "✅ Svelte mini app is ready"
      puts "All services are healthy!"

      # Run tests in sentry container with proper environment variables
      Dir.chdir('.devcontainer') do
        env_vars = {
          "SENTRY_E2E_RAILS_APP_URL" => "http://rails-mini:5000",
          "SENTRY_E2E_SVELTE_APP_URL" => "http://svelte-mini:5001"
        }
        env_string = env_vars.map { |k, v| "#{k}=#{v}" }.join(" ")

        unless system("#{env_string} docker-compose run --rm sentry bundle exec rspec spec/features/ --format progress")
          puts "E2E tests failed"
          exit(1)
        end
      end

    ensure
      # Always stop services
      Dir.chdir('.devcontainer') { system("docker-compose --profile e2e down") }
    end
  end
end

task default: :spec
