module Raven
  class Processor::Cookies < Processor
    def process(data)
      process_if_symbol_keys(data) if data[:request]
      process_if_string_keys(data) if data["request"]

      data
    end

    private

    def process_if_symbol_keys(data)
      if cookies = data.dig(:request, :cookies)
        data[:request][:cookies] = generate_masked_cookies(cookies)
      end

      if cookies_header = data[:request][:headers]["Cookie"]
        data[:request][:headers]["Cookie"] = generate_masked_cookies(cookies_header)
      end
    end

    def process_if_string_keys(data)
      if cookies = data.dig("request", "cookies")
        data["request"]["cookies"] = generate_masked_cookies(cookies)
      end

      if cookies_header = data.dig("request", "headers", "Cookie")
        data["request"]["headers"]["Cookie"] = generate_masked_cookies(cookies_header)
      end
    end

    def generate_masked_cookies(cookies)
      cookies.merge(cookies) { STRING_MASK } if cookies.respond_to?(:merge)
    end
  end
end
