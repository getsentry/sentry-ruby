require 'coveralls'
Coveralls.wear!

def build_exception
  1 / 0
rescue ZeroDivisionError => exception
  return exception
end
