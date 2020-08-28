require "raven/helpers/deprecation_helper"

filename = "raven/integrations/rack_timeout"
DeprecationHelper.deprecate_dasherized_filename(filename)

require filename
