require "raven/helpers/deprecation_helper"

filename = "sentry_raven_without_integrations"
DeprecationHelper.deprecate_dasherized_filename(filename)

require filename
