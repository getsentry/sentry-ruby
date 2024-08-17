# frozen_string_literal: true

require "fileutils"
require "rails/generators/test_case"
require "generators/sentry_generator"

behavior_module = if defined?(Rails::Generators::Testing::Behaviour)
  Rails::Generators::Testing::Behaviour
else
  Rails::Generators::Testing::Behavior
end

RSpec.describe SentryGenerator do
  include behavior_module
  include FileUtils
  self.destination File.expand_path('../../tmp', __dir__)
  self.generator_class = described_class

  let(:layout_file) do
    File.join(destination_root, "app/views/layouts/application.html.erb")
  end

  before do
    prepare_destination

    FileUtils.mkdir_p(File.dirname(layout_file))

    File.write(layout_file, <<~STR)
      <!DOCTYPE html>
      <html>
        <head>
          <title>SentryTesting</title>
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <%= csrf_meta_tags %>
          <%= csp_meta_tag %>

          <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
          <%= javascript_importmap_tags %>
        </head>

        <body>
          <%= yield %>
        </body>
      </html>
    STR
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
        config.enable_tracing = true
      end
    RUBY
  end

  it "injects meta tag into the layout" do
    run_generator

    content = File.read(layout_file)

    expect(content).to include("Sentry.get_trace_propagation_meta.html_safe")
  end

  it "doesn't inject meta tag when it's disabled" do
    run_generator %w[--inject-meta false]

    content = File.read(layout_file)

    expect(content).not_to include("Sentry.get_trace_propagation_meta.html_safe")
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
          config.enable_tracing = true
        end
      RUBY
    end
  end
end
