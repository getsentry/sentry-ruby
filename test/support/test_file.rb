def my_method
  Kernel.caller_locations
end

loc = my_method
puts loc
puts loc.first.absolute_path
