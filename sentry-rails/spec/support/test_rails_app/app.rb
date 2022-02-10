ENV["RAILS_ENV"] = "test"

require "rails"

require "active_record"
require "active_job/railtie"
require "action_view/railtie"
require "action_controller/railtie"

require 'sentry/rails'

ActiveSupport::Deprecation.silenced = true
ActiveRecord::Base.logger = Logger.new(nil)

# need to init app before establish connection so sqlite can place the database file under the correct project root
class TestApp < Rails::Application
end

v5_2 = Gem::Version.new("5.2")
v6_0 = Gem::Version.new("6.0")
v6_1 = Gem::Version.new("6.1")
v7_0 = Gem::Version.new("7.0")
v7_1 = Gem::Version.new("7.1")

case Gem::Version.new(Rails.version)
when -> (v) { v < v5_2 }
  require "support/test_rails_app/apps/5-0"
when -> (v) { v.between?(v5_2, v6_0) }
  require "support/test_rails_app/apps/5-2"
when -> (v) { v.between?(v6_0, v6_1) }
  require "support/test_rails_app/apps/6-0"
when -> (v) { v.between?(v6_1, v7_0) }
  require "support/test_rails_app/apps/6-1"
when -> (v) { v.between?(v7_0, v7_1) }
  require "support/test_rails_app/apps/7-0"
end
