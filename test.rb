begin
  def ohno
    1/0
  end
  ohno
rescue Exception => e
  @e = e
end

puts @e.backtrace_locations
puts @e.backtrace_locations.first.path
puts @e.backtrace_locations.first.to_s
require 'pry'; binding.pry
