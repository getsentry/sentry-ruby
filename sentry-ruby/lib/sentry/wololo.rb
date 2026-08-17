# frozen_string_literal: true

require "digest"
require "json"
require "thread"

module Sentry
  # Experimental, opt-in exception repair worker.
  #
  # Wololo deliberately keeps ruby_llm an optional dependency because the core
  # SDK still supports Rubies on which ruby_llm cannot be installed. It also
  # never sends anything until an exception has been captured and wololo has
  # been enabled explicitly.
  class Wololo < ThreadedPeriodicWorker
    INTERVAL = 10
    MAX_QUEUE = 10
    DEDUP_WINDOW = 300
    MAX_BACKTRACE_LINES = 20
    MAX_FILE_COUNT = 10
    MAX_FILE_BYTES = 50_000
    MAX_TOTAL_FILE_BYTES = 200_000
    MIN_CONFIDENCE = 0.9
    DEFAULT_MODEL = "deepseek/deepseek-v4-flash"
    FORBIDDEN_PATCH_METHODS = %w[
      initialize new allocate inherited method_missing respond_to_missing?
      method_added method_removed method_undefined
    ].freeze

    attr_reader :queue

    def initialize(configuration)
      super(configuration.sdk_logger, INTERVAL)
      @configuration = configuration
      @queue = SizedQueue.new(MAX_QUEUE)
      @deduplicated = {}
      @mutex = Mutex.new
      @patch_mutex = Mutex.new
      @registered_patches = []
      @rails_reloader_registered = false
      @sdk_logger = configuration.sdk_logger
      @project_root = File.realpath(configuration.project_root.to_s)
      @last_result = nil
    rescue SystemCallError
      @project_root = File.expand_path(configuration.project_root.to_s)
    end

    # Adds an exception to the repair queue. This method is intentionally
    # safe to call from an exception path: failures are swallowed and logged.
    #
    # @return [Boolean] whether the exception was queued
    def record(exception)
      return false unless exception.is_a?(Exception)

      issue = issue_from(exception)
      return false unless issue

      queued = @mutex.synchronize do
        prune_deduplication
        if @deduplicated.key?(issue[:fingerprint])
          log_debug("[Wololo] ignoring duplicate problem #{issue[:fingerprint]} (#{issue[:exception_class]}: #{issue[:message]})")
          next false
        end

        begin
          @queue.push(issue, true)
        rescue ThreadError
          next false
        end

        @deduplicated[issue[:fingerprint]] = monotonic_time
        true
      end

      ensure_thread if queued
      queued
    rescue Exception => e
      log_error("[Wololo] could not queue an exception", e, debug: @configuration.debug)
      false
    end

    # Processes all issues currently waiting in the queue. Kept public so
    # applications and tests can explicitly drain Wololo without waiting a
    # minute.
    def run
      issue = @queue.pop(true) rescue nil
      process(issue) if issue
    end

    private

    def process(issue)
      result = request_patch(issue)
      return unless result

      @last_result = result
      apply_patches(issue, result) if result[:confidence] >= MIN_CONFIDENCE
    rescue Exception => e
      log_error("[Wololo] failed to process an exception", e, debug: @configuration.debug)
    end

    def issue_from(exception)
      backtrace = Array(exception.backtrace).first(MAX_BACKTRACE_LINES)
      locations = backtrace.filter_map { |line| parse_location(line) }
      files = source_files(locations)
      return if files.empty?

      message = exception.message.to_s
      signature = [exception.class.name, message, backtrace.first(5)].join("\0")

      {
        fingerprint: Digest::SHA256.hexdigest(signature),
        exception_class: exception.class.name,
        message: message[0, 2_000],
        backtrace: backtrace,
        files: files
      }
    rescue StandardError => e
      log_error("[Wololo] could not inspect an exception", e, debug: @configuration.debug)
      nil
    end

    def parse_location(line)
      match = /\A(.+?):(\d+)(?::in .*)?\z/.match(line.to_s)
      return unless match

      { path: match[1], line: match[2].to_i }
    end

    def source_files(locations)
      result = []
      total_bytes = 0

      locations.each do |location|
        path = safe_source_path(location[:path])
        next unless path
        next if result.any? { |file| file[:path] == relative_path(path) }

        content = File.binread(path)
        next if content.include?("\x00")

        content = content.byteslice(0, [MAX_FILE_BYTES, MAX_TOTAL_FILE_BYTES - total_bytes].min)
        break if content.nil? || content.empty?

        result << {
          path: relative_path(path),
          line: location[:line],
          content: content.force_encoding(Encoding::UTF_8).scrub
        }
        total_bytes += content.bytesize
        break if result.size >= MAX_FILE_COUNT || total_bytes >= MAX_TOTAL_FILE_BYTES
      rescue SystemCallError, EncodingError
        next
      end

      result
    end

    def safe_source_path(path)
      expanded = File.expand_path(path.to_s, @project_root)
      return unless expanded == @project_root || expanded.start_with?("#{@project_root}#{File::SEPARATOR}")

      real = File.realpath(expanded)
      return unless real.start_with?("#{@project_root}#{File::SEPARATOR}")
      return unless File.file?(real)

      relative = relative_path(real)
      pattern = @configuration.app_dirs_pattern
      return if pattern && !pattern.match?(relative)

      real
    rescue SystemCallError
      nil
    end

    def relative_path(path)
      path.delete_prefix("#{@project_root}#{File::SEPARATOR}")
    end

    def request_patch(issue)
      begin
        require "ruby_llm"
      rescue LoadError => e
        log_warn("[Wololo] is enabled but ruby_llm is not installed: #{e.message}")
        return
      end

      RubyLLM.configure do |config|
        config.openrouter_api_key = @configuration.wololo_openrouter_api_key
      end

      prompt = <<~PROMPT
        You are repairing a Ruby application after a runtime exception.

        Return ONLY valid JSON. Do not use markdown fences, comments, or any
        text outside the JSON object. The exact shape is:
        {"confidence": 0.0, "patches": [{"file": "relative/path.rb", "target": "MyApp::SomeClass", "module": "def method_name\\n  ...\\nend"}]}

        The SDK applies each patch by evaluating the `module` value as the
        body of a new anonymous Ruby Module and prepending that Module to the
        class or module named by `target`. Therefore:
        - `module` must contain Ruby method definitions only.
        - Do not include a `module ... end` wrapper.
        - Do not include class-level code, expressions, registrations, or
          side effects outside method definitions.
        - Every method must be valid Ruby source on its own.

        Most important rule: a prepended method is a complete replacement for
        the original method. It runs in a new invocation with a new local
        variable scope. It cannot see or resume the original method's local
        variables or execution state. `super` only calls the original method
        from the beginning; it cannot continue after the line that raised.

        For every replacement method:
        1. Copy the complete behavior of the original method from the supplied
           source, not just the failing line or a small fragment.
        2. Re-create every local variable used by the replacement before it is
           read. Never reference a local merely because it existed in the
           original method.
        3. Preserve required setup, side effects, return values, rendering,
           callbacks, and error behavior unless changing them is necessary for
           the reported exception.
        4. Put the fix directly into the complete replacement method. Preserve
           all unaffected control flow and only change the behavior necessary
           to repair the reported exception.
        5. Do not move class-level declarations such as Rails
           `before_action`, `skip_forgery_protection`, routes, or associations
           into an instance method. They are not method-body code.

        Validation rules:
        - `confidence` must be a number between 0 and 1.
        - Only propose a patch when the supplied source proves the fix.
        - Treat the supplied source as the complete set of facts. Do not infer
          APIs, model behavior, method implementations, or intended semantics
          from names, conventions, or the exception message alone.
        - Every `file` must exactly match one of the supplied files.
        - `target` must be a class or module defined by the supplied source.
        - Each replacement must override an existing method defined in that
          file, and the method name must be relevant to the exception.
        - For `NoMethodError`, prove from the supplied source that the
          replacement removes the invalid call or that the called method is
          defined with the required behavior. If the receiver's implementation
          is not supplied, do not guess how to replace or implement the call;
          return an empty `patches` array.
        - Never preserve a call known to cause the reported exception unless
          the patch changes it in a way supported by the supplied source.
        - Never override `initialize`, `new`, `allocate`, `inherited`,
          `method_missing`, `respond_to_missing?`, or lifecycle/dispatch
          methods.
        - Do not add dependencies, execute shell commands, change credentials,
          weaken security, modify tests, or run top-level application code.
        - If the complete replacement cannot be reconstructed safely, return
          an empty `patches` array instead of guessing.

        Before producing JSON, silently verify that every bare identifier in
        each replacement that is intended to be a local variable is assigned
        within that replacement. Silently verify that the replacement includes
        the original method's required setup and does not contain unrelated
        class-level declarations.

        Exception:
        #{issue[:exception_class]}: #{issue[:message]}

        Backtrace:
        #{issue[:backtrace].join("\n")}

        Source files (the line field identifies a relevant stack frame):
        #{JSON.generate(issue[:files])}
      PROMPT

      chat = RubyLLM.chat(
        model: ENV.fetch("SENTRY_WOLOLO_MODEL", DEFAULT_MODEL),
        provider: "openrouter"
      ).with_params(reasoning: { effort: "high" })
      log_debug("[Wololo] making LLM request with model #{ENV.fetch("SENTRY_WOLOLO_MODEL", DEFAULT_MODEL)}")
      response = chat.ask(prompt)
      content = response.respond_to?(:content) ? response.content : response.to_s
      response_json = content.to_s[/\{.*\}/m] || content.to_s
      pretty_response = begin
        JSON.pretty_generate(JSON.parse(response_json))
      rescue JSON::ParserError
        response_json
      end
      log_debug("[Wololo] received LLM response:\n#{pretty_response}")
      parsed = JSON.parse(response_json)
      normalize_result(parsed, issue)
    rescue StandardError => e
      log_error("[Wololo] LLM request failed", e, debug: @configuration.debug)
      nil
    end

    def normalize_result(result, issue)
      return unless result.is_a?(Hash)

      confidence = Float(result["confidence"] || result[:confidence])
      patches = result["patches"] || result[:patches]
      return unless confidence.between?(0.0, 1.0) && patches.is_a?(Array)

      normalized = patches.filter_map do |patch|
        next unless patch.is_a?(Hash)

        file = patch["file"] || patch[:file]
        target = patch["target"] || patch[:target]
        source = patch["module"] || patch[:module]
        next unless file.is_a?(String) && target.is_a?(String) && source.is_a?(String)
        next unless target.match?(/\A[A-Z]\w*(?:::[A-Z]\w*)*\z/)
        next unless patch_source_allowed?(source)

        { file: file, target: target, module: source }
      end

      return if normalized.empty?

      { confidence: confidence, patches: normalized }
    rescue ArgumentError, TypeError
      nil
    end

    def apply_patches(issue, result)
      allowed_files = issue[:files].to_h { |file| [file[:path], file[:content]] }
      patches = result[:patches].map do |patch|
        path = safe_source_path(patch[:file])
        unless path && allowed_files.key?(relative_path(path))
          log_warn("[Wololo] rejected patch for #{patch[:file]}: file is not an allowed source file")
          next
        end
        unless module_source_valid?(patch[:module], path)
          log_warn("[Wololo] rejected patch for #{patch[:file]}: module has invalid Ruby syntax")
          next
        end
        unless patch_source_allowed?(patch[:module])
          log_warn("[Wololo] rejected patch for #{patch[:target]}: patch contains a forbidden method")
          next
        end

        target = resolve_target(patch[:target])
        unless target.is_a?(Module)
          log_warn("[Wololo] rejected patch: target #{patch[:target]} is not a loaded class or module")
          next
        end
        unless target_source_matches?(target, patch[:module], path)
          log_warn("[Wololo] rejected patch: #{patch[:target]} is not defined by #{relative_path(path)}")
          next
        end

        { target: patch[:target], source: patch[:module], path: path }
      end

      if patches.empty?
        log_debug("[Wololo] no applicable prepend patches found")
        return
      end

      if patches.any?(&:nil?)
        log_warn("[Wololo] rejected prepend patches because at least one patch was invalid")
        return
      end

      @patch_mutex.synchronize do
        patches.each do |patch|
          apply_prepend_patch(patch[:target], patch[:source], patch[:path])
          @registered_patches << patch unless @registered_patches.include?(patch)
        end
      end
      register_rails_reloader
      log_debug("[Wololo] applied #{patches.size} prepend patch(es) with confidence #{result[:confidence]}")
    rescue Exception => e
      log_error("[Wololo] rejected a prepend patch", e, debug: @configuration.debug)
    end

    def apply_prepend_patch(target_name, source, path)
      target = resolve_target(target_name)
      return unless target.is_a?(Module)
      return if target.ancestors.any? { |ancestor| ancestor.instance_variable_get(:@sentry_wololo_patch) == [target_name, source] }

      log_debug(<<~MESSAGE.chomp)
        [Wololo] applying prepend patch to #{target} from #{relative_path(path)}
        Patch:
        #{JSON.pretty_generate({ file: relative_path(path), target: target_name })}
        module:
        #{source}
      MESSAGE
      # Evaluate at top level so bare constants in the patch resolve like they
      # do in the application file. Evaluating here with module_eval would
      # make names such as `Redis` resolve to `Sentry::Redis` because this
      # method is lexically nested under Sentry.
      patch_module = TOPLEVEL_BINDING.eval("Module.new {\n#{source}\n}", path, 1)
      patch_module.instance_variable_set(:@sentry_wololo_patch, [target_name, source])
      target.prepend(patch_module)
      log_debug("[Wololo] target ancestors after prepend: #{target.ancestors.first(4).map(&:to_s).join(", ")}")
    end

    def register_rails_reloader
      return if @rails_reloader_registered
      return unless defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application

      reloader = ::Rails.application.reloader
      return unless reloader.respond_to?(:to_prepare)

      reloader.to_prepare { reapply_registered_patches }
      @rails_reloader_registered = true
      log_debug("[Wololo] registered Rails reloader callback")
    rescue Exception => e
      log_error("[Wololo] could not register Rails reloader callback", e, debug: @configuration.debug)
    end

    def reapply_registered_patches
      @patch_mutex.synchronize do
        @registered_patches.each do |patch|
          apply_prepend_patch(patch[:target], patch[:source], patch[:path])
        end
      end
    rescue Exception => e
      log_error("[Wololo] could not reapply Rails prepend patches", e, debug: @configuration.debug)
    end

    def resolve_target(name)
      name.split("::").reject(&:empty?).reduce(Object) do |namespace, constant|
        return unless namespace.is_a?(Module) && namespace.const_defined?(constant, false)

        namespace.const_get(constant, false)
      end
    rescue NameError, TypeError
      nil
    end

    def patch_source_allowed?(source)
      method_names = source.scan(/^\s*def\s+(?:self\.)?([a-zA-Z_][a-zA-Z0-9_!?=]*)/).flatten
      (method_names & FORBIDDEN_PATCH_METHODS).empty?
    end

    def target_source_matches?(target, source, path)
      method_names = source.scan(/^\s*def\s+([a-zA-Z_][a-zA-Z0-9_!?=]*)/).flatten
      return false if method_names.empty?

      method_names.any? do |method_name|
        next false unless target.method_defined?(method_name) || target.private_method_defined?(method_name)

        source_location = target.instance_method(method_name).source_location&.first
        next false unless source_location && File.expand_path(source_location) == File.expand_path(path)

        patch_locals_match?(target.instance_method(method_name), source, path, method_name)
      end
    rescue NameError
      false
    end

    # Methods added through a prepend do not share the local-variable scope of
    # the method they replace. Ruby treats an unresolved bare name as a method
    # call, which turns a missing local into a later and rather confusing
    # NameError (for example, `payment` in a repair for `checkout`). Reject
    # patches that accidentally rely on locals from the original method.
    def patch_locals_match?(original_method, source, path, method_name)
      original_iseq = RubyVM::InstructionSequence.of(original_method)
      patch_iseq = find_method_iseq(
        RubyVM::InstructionSequence.compile("Module.new {\n#{source}\n}", path).to_a,
        method_name
      )
      return false unless original_iseq && patch_iseq

      original_locals = original_iseq.to_a[10]
      patch_locals = patch_iseq[10]
      unresolved_calls = zero_argument_calls(patch_iseq) - patch_locals

      (unresolved_calls & original_locals).empty?
    rescue SyntaxError, StandardError
      false
    end

    def find_method_iseq(value, method_name)
      return unless value.is_a?(Array)
      return value if value.first == "YARVInstructionSequence/SimpleDataFormat" && value[5] == method_name && value[9] == :method

      value.each do |child|
        found = find_method_iseq(child, method_name)
        return found if found
      end

      nil
    end

    def zero_argument_calls(value)
      calls = []
      walk = lambda do |child|
        if child.is_a?(Array)
          if %i[send opt_send_without_block].include?(child.first) && child[1].is_a?(Hash) && child[1][:orig_argc] == 0
            calls << child[1][:mid]
          end
          child.each { |nested| walk.call(nested) }
        end
      end
      walk.call(value)
      calls.compact.uniq
    end

    def module_source_valid?(source, path)
      return false unless defined?(RubyVM::InstructionSequence)

      RubyVM::InstructionSequence.compile("Module.new {\n#{source}\n}", path)
      true
    rescue SyntaxError, StandardError
      false
    end

    def prune_deduplication
      cutoff = monotonic_time - DEDUP_WINDOW
      @deduplicated.delete_if { |_fingerprint, timestamp| timestamp < cutoff }
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
