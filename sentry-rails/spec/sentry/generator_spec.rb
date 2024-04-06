# frozen_string_literal: true

require "fileutils"
require "rails/generators/test_case"
require "generators/sentry_generator"

RSpec.describe SentryGenerator do
  include ::Rails::Generators::Testing::Behaviour
  include FileUtils
  self.destination File.expand_path('../../tmp', __dir__)
  self.generator_class = described_class

  before do
    prepare_destination
  end

  it "creates a initializer file" do
    run_generator

    file = File.join(destination_root, "config/initializers/sentry.rb")
    expect(File).to exist(file)
    content = File.read(file)
    expect(content).to include(<<~RUBY)
      Sentry.init do |config|
        config.breadcrumbs_logger = [:active_support_logger]
        config.dsn = ENV['SENTRY_DSN']
      end
    RUBY
  end

  context "with a DSN option" do
    it "creates a initializer file with the DSN" do
      run_generator %w[--dsn foobarbaz]

      file = File.join(destination_root, "config/initializers/sentry.rb")
      expect(File).to exist(file)
      content = File.read(file)
      expect(content).to include(<<~RUBY)
        Sentry.init do |config|
          config.breadcrumbs_logger = [:active_support_logger]
          config.dsn = 'foobarbaz'
        end
      RUBY
    end
  end
end
