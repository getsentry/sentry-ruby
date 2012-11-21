# Copyright (c) 2005-2012 David Heinemeier Hansson

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# This code is heavily inspired by Rails::BacktraceCleaner

module Raven
  # Backtraces often include many lines that are not relevant for the context
  # under review. This makes it hard to find the signal amongst the backtrace
  # noise, and adds debugging time. With a BacktraceCleaner, filters and
  # silencers are used to remove the noisy lines, so that only the most relevant
  # lines remain.
  #
  # Filters are used to modify lines of data, while silencers are used to remove
  # lines entirely. The typical filter use case is to remove lengthy path
  # information from the start of each line, and view file paths relevant to the
  # app directory instead of the file system root. The typical silencer use case
  # is to exclude the output of a noisy library from the backtrace, so that you
  # can focus on the rest.
  #
  #   bc = BacktraceCleaner.new
  #   bc.add_filter   { |line| line.gsub(Rails.root, '') }
  #   bc.add_silencer { |line| line =~ /mongrel|rubygems/ }
  #   bc.clean(exception.backtrace) # will strip the Rails.root prefix and skip any lines from mongrel or rubygems
  #
  # To reconfigure an existing BacktraceCleaner (like the default one in Rails)
  # and show as much data as possible, you can always call
  # <tt>BacktraceCleaner#remove_silencers!</tt>, which will restore the
  # backtrace to a pristine state. If you need to reconfigure an existing
  # BacktraceCleaner so that it does not filter or modify the paths of any lines
  # of the backtrace, you can call BacktraceCleaner#remove_filters! These two
  # methods will give you a completely untouched backtrace.
  #
  # Inspired by the Quiet Backtrace gem by Thoughtbot.
  class BacktraceCleaner
    APP_DIRS_PATTERN = /^\/?(app|config|lib|test)/
    RENDER_TEMPLATE_PATTERN = /:in `_render_template_\w*'/

    def initialize
      @filters, @silencers = [], []
      if defined? ::Rails
        add_filter   { |line| line.sub("#{::Rails.root}/", '') }
        add_filter   { |line| line.sub(RENDER_TEMPLATE_PATTERN, '') }
        add_silencer { |line| line !~ APP_DIRS_PATTERN }
      end

      add_filter   { |line| line.sub('./', '/') } # for tests

      add_gem_filters      
    end

    # Returns the backtrace after all filters and silencers have been run
    # against it. Filters run first, then silencers.
    def clean(backtrace)
      filtered = filter_backtrace(backtrace)

      backtrace.reverse.map do |trace_line|
        in_app = frame_in_app?(trace_line)
        [trace_line, in_app]
      end
    end

    def frame_in_app?(trace_line)
      @silencers.any? do |s|
        s.call(trace_line)
      end
    end


    # Adds a filter from the block provided. Each line in the backtrace will be
    # mapped against this filter.
    #
    #   # Will turn "/my/rails/root/app/models/person.rb" into "/app/models/person.rb"
    #   backtrace_cleaner.add_filter { |line| line.gsub(Rails.root, '') }
    def add_filter(&block)
      @filters << block
    end

    # Adds a silencer from the block provided. If the silencer returns +true+
    # for a given line, it will be excluded from the clean backtrace.
    #
    #   # Will reject all lines that include the word "mongrel", like "/gems/mongrel/server.rb" or "/app/my_mongrel_server/rb"
    #   backtrace_cleaner.add_silencer { |line| line =~ /mongrel/ }
    def add_silencer(&block)
      @silencers << block
    end

    # Will remove all silencers, but leave in the filters. This is useful if
    # your context of debugging suddenly expands as you suspect a bug in one of
    # the libraries you use.
    def remove_silencers!
      @silencers = []
    end

    def remove_filters!
      @filters = []
    end

    private
      def add_gem_filters
        gems_paths = (Gem.path | [Gem.default_dir]).map { |p| Regexp.escape(p) }
        return if gems_paths.empty?

        gems_regexp = %r{(#{gems_paths.join('|')})/gems/([^/]+)-([\w.]+)/(.*)}
        add_filter { |line| line.sub(gems_regexp, '\2 (\3) \4') }
      end

      def filter_backtrace(backtrace)
        @filters.each do |f|
          backtrace = backtrace.map { |line| f.call(line) }
        end

        backtrace
      end
  end
end


