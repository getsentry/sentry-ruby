module DeprecationHelper
  def self.deprecate_dasherized_filename(correct_filename)
    warn "[Deprecation Warning] Dasherized filename \"#{correct_filename.gsub('_', '-')}\" is deprecated and will be removed in 4.0; use \"#{correct_filename}\" instead" # rubocop:disable Style/LineLength
  end
end
