# A much simpler source line cacher because linecache sucks at platform compat

module Raven

  class LineCache
    class << self
      CACHE = {}

      def getlines(path)
        CACHE[path] ||= begin
          IO.readlines(path)
        rescue
          []
        end
      end

      def getline(path, n)
        return nil if n < 1
        getlines(path)[n-1]
      end

    end
  end

end
