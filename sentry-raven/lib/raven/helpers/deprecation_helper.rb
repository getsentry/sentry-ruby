module DeprecationHelper
  def self.deprecate_dasherized_filename(correct_filename)
    warn "[Deprecation Warning] Dasherized filename \"#{correct_filename.gsub('_', '-')}\" is deprecated and will be removed in 4.0; use \"#{correct_filename}\" instead" # rubocop:disable Style/LineLength
  end

  def self.deprecate_old_breadcrumbs_configuration(logger)
    deprecated_usage =
      if logger == :sentry_logger
        "require \"raven/breadcrumbs/logger\""
      else
        "Raven.configuration.rails_activesupport_breadcrumbs = true"
      end
    recommended_usage = "Raven.configuration.breadcrumbs_logger = :#{logger}"

    warn "[Deprecation Warning] The way you enable breadcrumbs logger (#{deprecated_usage}) is deprecated and will be removed in 4.0; use '#{recommended_usage}' instead" # rubocop:disable Style/LineLength
  end
end
