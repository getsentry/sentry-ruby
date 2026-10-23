# frozen_string_literal: true

RSpec.describe "Sentry job extensions" do
  let(:extension_class) do
    Class.new(Sentry::JobExtensions::Extension) do
      def initialize(name:, claim_check:)
        super(name: name)
        @claim_check = claim_check
      end

      def handles?(job)
        @claim_check.call(job)
      end
    end
  end

  let(:sidekiq_job) { double("job", adapter: "sidekiq") }
  let(:good_job_job) { double("job", adapter: "good_job") }

  def build_extension(name, claims: ->(job) { job.adapter == name })
    extension_class.new(name: name, claim_check: claims)
  end

  after { Sentry.job_extensions.clear }

  describe ".register_job_extension" do
    it "makes an extension available before Sentry is initialized" do
      extension = build_extension("sidekiq")

      Sentry.register_job_extension(extension)

      expect(Sentry.initialized?).to eq(false)
      expect(Sentry.job_extensions.for(sidekiq_job)).to be(extension)
    end

    it "makes an extension available after Sentry is initialized" do
      perform_basic_setup
      extension = build_extension("sidekiq")

      Sentry.register_job_extension(extension)

      expect(Sentry.job_extensions.for(sidekiq_job)).to be(extension)
    end

    it "keeps registrations across Sentry re-initialization" do
      extension = build_extension("sidekiq")
      Sentry.register_job_extension(extension)

      perform_basic_setup

      expect(Sentry.job_extensions.for(sidekiq_job)).to be(extension)
    end

    it "rejects an extension whose name is already registered and keeps the original" do
      original = build_extension("sidekiq")
      Sentry.register_job_extension(original)

      expect { Sentry.register_job_extension(build_extension("sidekiq")) }
        .to raise_error(ArgumentError, /sidekiq/)
      expect(Sentry.job_extensions.for(sidekiq_job)).to be(original)
    end

    it "rejects an object that is not an extension instance and keeps existing registrations" do
      extension = build_extension("sidekiq")
      Sentry.register_job_extension(extension)
      duck = double("duck", name: "good_job", handles?: true)

      expect { Sentry.register_job_extension(duck) }.to raise_error(ArgumentError)
      expect { Sentry.register_job_extension(extension_class) }.to raise_error(ArgumentError)
      expect(Sentry.job_extensions.for(sidekiq_job)).to be(extension)
      expect(Sentry.job_extensions.for(good_job_job)).to be_nil
    end
  end

  describe "Sentry::JobExtensions::Extension" do
    it "rejects a blank name" do
      expect { build_extension("") }.to raise_error(ArgumentError)
      expect { build_extension(nil) }.to raise_error(ArgumentError)
    end

    it "does not claim any job by default" do
      Sentry.register_job_extension(Sentry::JobExtensions::Extension.new(name: "noop"))

      expect(Sentry.job_extensions.for(sidekiq_job)).to be_nil
    end
  end

  describe "#for" do
    it "returns the extension that claims the job" do
      sidekiq = build_extension("sidekiq")
      good_job = build_extension("good_job")
      Sentry.register_job_extension(sidekiq)
      Sentry.register_job_extension(good_job)

      expect(Sentry.job_extensions.for(good_job_job)).to be(good_job)
    end

    it "returns nil when no extension claims the job" do
      Sentry.register_job_extension(build_extension("sidekiq"))

      expect(Sentry.job_extensions.for(good_job_job)).to be_nil
    end

    it "returns the earliest registered extension when several claim the job" do
      first = build_extension("first", claims: ->(_job) { true })
      second = build_extension("second", claims: ->(_job) { true })
      Sentry.register_job_extension(first)
      Sentry.register_job_extension(second)

      expect(Sentry.job_extensions.for(sidekiq_job)).to be(first)
    end

    context "when a claim check raises a StandardError" do
      let(:string_io) { StringIO.new }
      let(:broken) { build_extension("broken", claims: ->(_job) { raise "claim failed" }) }

      before do
        perform_basic_setup { |config| config.sdk_logger = Logger.new(string_io) }
      end

      it "logs the failure and considers the remaining extensions" do
        sidekiq = build_extension("sidekiq")
        Sentry.register_job_extension(broken)
        Sentry.register_job_extension(sidekiq)

        expect(Sentry.job_extensions.for(sidekiq_job)).to be(sidekiq)
        expect(string_io.string).to include("broken", "claim failed")
      end

      it "returns nil when no other extension claims the job" do
        Sentry.register_job_extension(broken)

        expect(Sentry.job_extensions.for(sidekiq_job)).to be_nil
      end
    end

    it "treats a raising claim check as not claiming when Sentry is not initialized" do
      Sentry.register_job_extension(build_extension("broken", claims: ->(_job) { raise "claim failed" }))

      expect(Sentry.job_extensions.for(sidekiq_job)).to be_nil
    end

    it "propagates exceptions outside StandardError from a claim check" do
      Sentry.register_job_extension(build_extension("interrupted", claims: ->(_job) { raise Interrupt }))

      expect { Sentry.job_extensions.for(sidekiq_job) }.to raise_error(Interrupt)
    end
  end

  describe "#with_default" do
    let(:default_extension) do
      build_extension("default", claims: ->(_job) { true }).tap do |extension|
        extension.define_singleton_method(:transaction_name) { |job:| "Default/#{job.adapter}" }
        extension.define_singleton_method(:report_retried_exception?) { |job:, exception:| true }
      end
    end
    let(:registry) { Sentry.job_extensions.with_default(default_extension) }

    it "uses the default until a matching backend is registered" do
      expect(registry.call(registry.for(sidekiq_job), :transaction_name, job: sidekiq_job)).to eq("Default/sidekiq")
      backend = build_extension("sidekiq")
      backend.define_singleton_method(:transaction_name) { |job:| "SidekiqJob" }

      Sentry.register_job_extension(backend)

      expect(registry.call(registry.for(sidekiq_job), :transaction_name, job: sidekiq_job)).to eq("SidekiqJob")
      expect(registry.call(registry.for(good_job_job), :transaction_name, job: good_job_job)).to eq("Default/good_job")
    end

    it "uses only the selected extension and preserves its false decision" do
      backend = build_extension("sidekiq")
      backend.define_singleton_method(:report_retried_exception?) { |job:, exception:| false }
      Sentry.register_job_extension(backend)

      extension = registry.for(sidekiq_job)

      expect(extension).to equal(backend)
      expect(registry.call(extension, :transaction_name, job: sidekiq_job)).to be_nil
      expect(registry.call(extension, :report_retried_exception?, job: sidekiq_job, exception: RuntimeError.new)).to be(false)
    end

    context "with default trace propagation" do
      let(:payload) { { "class" => "ExampleJob", "args" => [] } }
      let(:headers) { { "sentry-trace" => "#{"a" * 32}-#{"b" * 16}-1" } }
      let(:default_extension) do
        Class.new(Sentry::JobExtensions::Extension) do
          def inject_trace_headers(job:, payload:, headers:)
            payload.merge("sentry" => headers)
          end

          def extract_trace_headers(job:, payload:)
            payload["sentry"]
          end
        end.new(name: "default")
      end

      it "preserves the default trace when the backend only supplies metadata" do
        backend = Class.new(default_extension.class) do
          def handles?(job)
            job.adapter == "sidekiq"
          end

          def scope_data(job:)
            { tags: { queue: "default" } }
          end
        end.new(name: "sidekiq")
        Sentry.register_job_extension(backend)
        extension = registry.for(sidekiq_job)

        injected = registry.call(extension, :inject_trace_headers, job: sidekiq_job, payload: payload, headers: headers)

        expect(injected).to eq(payload.merge("sentry" => headers))
        expect(registry.call(extension, :extract_trace_headers, job: sidekiq_job, payload: injected)).to eq(headers)
        expect(payload).to eq("class" => "ExampleJob", "args" => [])
      end

      it "lets the backend add its headers to the default payload" do
        backend = Class.new(default_extension.class) do
          def handles?(job)
            job.adapter == "sidekiq"
          end

          def inject_trace_headers(job:, payload:, headers:)
            super.merge("backend_trace" => headers)
          end
        end.new(name: "sidekiq")
        Sentry.register_job_extension(backend)
        extension = registry.for(sidekiq_job)

        injected = registry.call(extension, :inject_trace_headers, job: sidekiq_job, payload: payload, headers: headers)

        expect(injected).to eq(payload.merge("sentry" => headers, "backend_trace" => headers))
        expect(registry.call(extension, :extract_trace_headers, job: sidekiq_job, payload: injected)).to eq(headers)
      end
    end
  end

  describe "#call" do
    let(:hooked_extension_class) do
      Class.new(Sentry::JobExtensions::Extension) do
        def initialize(name:, hooks:)
          super(name: name)
          hooks.each { |hook, implementation| define_singleton_method(hook, &implementation) }
        end
      end
    end

    let(:job) { double("job", jid: "abc123", queue: "default", retry_count: 2) }
    let(:exception) { RuntimeError.new("job failed") }
    let(:payload) { { "class" => "HardJob", "args" => [1] } }
    let(:headers) { { "sentry-trace" => "trace-value", "baggage" => "baggage-value" } }
    let(:string_io) { StringIO.new }
    let(:backend_integration) do
      Module.new do
        extend Sentry::Integrable

        def self.integration_name
          "backend"
        end
      end
    end

    let(:hook_arguments) do
      {
        scope_data: { job: job },
        error_data: { job: job, exception: exception },
        retry_info: { job: job },
        report_retried_exception?: { job: job, exception: exception },
        inject_trace_headers: { job: job, payload: payload, headers: headers },
        extract_trace_headers: { job: job, payload: payload },
        messaging_data: { job: job },
        transaction_name: { job: job },
        span_origin: { job: job },
        publish_description: { job: job },
        integration: { job: job },
        producer: { job: job },
        publish_messaging_data: { job: job }
      }
    end

    let(:fallback_results) do
      {
        scope_data: {},
        error_data: {},
        retry_info: nil,
        report_retried_exception?: nil,
        inject_trace_headers: payload,
        extract_trace_headers: nil,
        messaging_data: {},
        transaction_name: nil,
        span_origin: nil,
        publish_description: nil,
        integration: nil,
        producer: nil,
        publish_messaging_data: {}
      }
    end

    def build_hooked_extension(**hooks)
      hooked_extension_class.new(name: "sidekiq", hooks: hooks)
    end

    def call_hook(extension, hook)
      Sentry.job_extensions.call(extension, hook, **hook_arguments.fetch(hook))
    end

    def call_every_hook(extension)
      hook_arguments.keys.to_h { |hook| [hook, call_hook(extension, hook)] }
    end

    before do
      perform_basic_setup { |config| config.sdk_logger = Logger.new(string_io) }
    end

    it "uses custom validators without changing validation for other extensions" do
      validators = Class.new(Sentry::JobExtensions::Validators) do
        def label(result, **)
          super(result.is_a?(Symbol) ? result.to_s : result)
        end
      end.new
      custom = Class.new(Sentry::JobExtensions::Extension) do
        def transaction_name(job:)
          :CustomJob
        end
      end
      extension = custom.new(name: "custom", validators: validators)
      default_extension = custom.new(name: "default")

      expect(call_hook(extension, :transaction_name)).to eq("CustomJob")
      expect(call_hook(default_extension, :transaction_name)).to be_nil
      expect(call_hook(nil, :transaction_name)).to be_nil
    end

    it "uses configured metadata keys without following later changes to the supplied rules" do
      scope_keys = [:tags]
      event_keys = [:extra]
      validators = Sentry::JobExtensions::Validators.new(scope_keys: scope_keys, event_keys: event_keys)
      custom = Class.new(Sentry::JobExtensions::Extension) do
        def scope_data(job:)
          { tags: { queue: "default" }, user: { id: "42" } }
        end

        def error_data(job:, exception:)
          { tags: { failed: true }, extra: { attempt: 2 } }
        end
      end
      extension = custom.new(name: "custom", validators: validators)
      scope_keys << :user
      event_keys << :tags

      expect(call_hook(extension, :scope_data)).to eq(tags: { queue: "default" })
      expect(call_hook(extension, :error_data)).to eq(extra: { attempt: 2 })
      expect(call_hook(custom.new(name: "default"), :scope_data))
        .to eq(tags: { queue: "default" }, user: { id: "42" })
    end

    it "uses configured messaging validators without changing other extensions or following rule mutations" do
      fields = Sentry::JobExtensions::Validators::MESSAGING_DATA_VALIDATORS.merge(
        message_id: ->(value) { value.is_a?(String) && !value.empty? }
      )
      validators = Sentry::JobExtensions::Validators.new(messaging_fields: fields)
      custom = Class.new(Sentry::JobExtensions::Extension) do
        def messaging_data(job:)
          { system: "sidekiq", message_id: job }
        end
      end
      extension = custom.new(name: "custom", validators: validators)
      default_extension = custom.new(name: "default")
      fields[:message_id] = ->(**) { true }

      expect(Sentry.job_extensions.call(extension, :messaging_data, job: "abc123"))
        .to eq(system: "sidekiq", message_id: "abc123")
      expect(Sentry.job_extensions.call(extension, :messaging_data, job: "")).to eq({})
      expect(Sentry.job_extensions.call(default_extension, :messaging_data, job: ""))
        .to eq(system: "sidekiq", message_id: "")
    end

    it "returns the scope contexts and tags an extension derives from the job" do
      extension = build_hooked_extension(
        scope_data: lambda do |job:|
          { contexts: { sidekiq: { jid: job.jid } }, tags: { queue: job.queue } }
        end
      )

      expect(call_hook(extension, :scope_data))
        .to eq(contexts: { sidekiq: { jid: "abc123" } }, tags: { queue: "default" })
    end

    it "returns the event tags, extra and contexts an extension derives from the job and exception" do
      extension = build_hooked_extension(
        error_data: lambda do |job:, exception:|
          {
            tags: { queue: job.queue },
            extra: { error_message: exception.message },
            contexts: { sidekiq: { jid: job.jid } }
          }
        end
      )

      expect(call_hook(extension, :error_data)).to eq(
        tags: { queue: "default" },
        extra: { error_message: "job failed" },
        contexts: { sidekiq: { jid: "abc123" } }
      )
    end

    it "returns the retry count and policy an extension derives from the job" do
      extension = build_hooked_extension(
        retry_info: ->(job:) { { count: job.retry_count, will_retry: job.retry_count < 5 } }
      )

      expect(call_hook(extension, :retry_info)).to eq(count: 2, will_retry: true)
    end

    it "returns a payload carrying the trace headers" do
      extension = build_hooked_extension(
        inject_trace_headers: ->(job:, payload:, headers:) { payload.merge("sentry" => headers) }
      )

      expect(call_hook(extension, :inject_trace_headers))
        .to eq("class" => "HardJob", "args" => [1], "sentry" => headers)
    end

    it "returns the trace headers an extension reads from the payload" do
      carrying_payload = { "class" => "HardJob", "sentry" => headers }
      extension = build_hooked_extension(extract_trace_headers: ->(job:, payload:) { payload["sentry"] })

      expect(Sentry.job_extensions.call(extension, :extract_trace_headers, job: job, payload: carrying_payload)).to eq(headers)
    end

    it "returns the messaging span data an extension derives from the job" do
      extension = build_hooked_extension(
        messaging_data: lambda do |job:|
          { system: "sidekiq", message_id: job.jid, destination: job.queue, receive_latency: 1500, body_size: 42 }
        end
      )

      expect(call_hook(extension, :messaging_data))
        .to eq(system: "sidekiq", message_id: "abc123", destination: "default", receive_latency: 1500, body_size: 42)
    end

    it "returns the names an extension gives the job and the integration it captures errors under" do
      integration = backend_integration
      extension = build_hooked_extension(
        transaction_name: ->(job:) { "Backend/#{job.queue}" },
        span_origin: ->(job:) { "auto.queue.backend" },
        publish_description: ->(job:) { "publish #{job.jid}" },
        integration: ->(job:) { integration }
      )

      expect(call_every_hook(extension)).to include(
        transaction_name: "Backend/default",
        span_origin: "auto.queue.backend",
        publish_description: "publish abc123",
        integration: backend_integration
      )
    end

    it "returns the producer an extension supplies for enqueueing the job" do
      producer = Sentry::JobExtensions::Producer::Delegated.new
      extension = build_hooked_extension(producer: ->(job:) { producer })

      expect(call_hook(extension, :producer)).to be(producer)
    end

    it "returns the fallback result of every hook an extension does not override" do
      extension = build_hooked_extension(scope_data: ->(job:) { { tags: { queue: "default" } } })

      expect(call_every_hook(extension))
        .to eq(fallback_results.merge(scope_data: { tags: { queue: "default" } }))
    end

    it "returns the fallback result of every hook for a bare extension" do
      extension = Sentry::JobExtensions::Extension.new(name: "noop")

      expect(call_every_hook(extension)).to eq(fallback_results)
    end

    it "returns the fallback result of every hook when no extension claims the job" do
      expect(call_every_hook(nil)).to eq(fallback_results)
    end

    it "rejects a hook that is not part of the contract" do
      expect { Sentry.job_extensions.call(build_hooked_extension, :handles?, job: job) }
        .to raise_error(ArgumentError, /handles\?/)
    end

    it "logs and returns the fallback result when a hook raises a StandardError" do
      failing_hooks = hook_arguments.keys.to_h { |hook| [hook, ->(**) { raise "#{hook} exploded" }] }
      extension = build_hooked_extension(**failing_hooks)

      expect(call_every_hook(extension)).to eq(fallback_results)
      hook_arguments.each_key do |hook|
        expect(string_io.string).to include("sidekiq", hook.to_s, "#{hook} exploded")
      end
    end

    it "returns the fallback result when a hook raises and Sentry is not initialized" do
      reset_sentry_globals!
      extension = build_hooked_extension(scope_data: ->(job:) { raise "scope exploded" })

      expect(call_hook(extension, :scope_data)).to eq({})
    end

    it "propagates exceptions outside StandardError from a hook" do
      extension = build_hooked_extension(retry_info: ->(job:) { raise Interrupt })

      expect { call_hook(extension, :retry_info) }.to raise_error(Interrupt)
    end

    {
      scope_data: [{ tags: { queue: "default" }, body: "x" }, { tags: { queue: "default" } }],
      error_data: [{ extra: { attempt: 1 }, unknown: nil }, { extra: { attempt: 1 } }],
      retry_info: [{ count: 2, will_retry: true, backoff: 30 }, { count: 2, will_retry: true }],
      messaging_data: [{ system: "sidekiq", payload: "{}" }, { system: "sidekiq" }]
    }.each do |hook, (result, known_data)|
      it "keeps the documented data and drops unknown keys when #{hook} returns #{result.inspect}" do
        extension = build_hooked_extension(hook => ->(**) { result })

        expect(call_hook(extension, hook)).to eq(known_data)
        expect(string_io.string).not_to include("malformed")
      end
    end

    it "does not write a malformed result into the log" do
      extension = build_hooked_extension(inject_trace_headers: ->(job:, payload:, headers:) { payload["args"].map(&:to_s) })

      expect(call_hook(extension, :inject_trace_headers)).to eq(payload)
      expect(string_io.string).to include("sidekiq", "inject_trace_headers", "Array")
      expect(string_io.string).not_to include('"1"')
    end

    {
      scope_data: [nil, [], { contexts: { sidekiq: "jid" } }, { tags: [] }, { user: "42" }],
      error_data: [nil, "tags", { extra: nil }, { contexts: { sidekiq: 1 } }],
      retry_info: [{}, 2, { count: "2", will_retry: true }, { count: -1, will_retry: true },
                   { count: 2, will_retry: "yes" }, { count: 2 }],
      inject_trace_headers: [nil, "payload"],
      extract_trace_headers: ["sentry-trace", [], { "sentry-trace" => 1 }, { sentry_trace: "trace" }],
      messaging_data: [nil, [], { system: :sidekiq }, { message_id: 1 }, { destination: nil },
                       { receive_latency: "fast" }, { body_size: -1 }, { body_size: 1.5 }, { body_size: "42" }],
      transaction_name: ["", :HardJob, 1],
      span_origin: ["", :"auto.queue.backend"],
      publish_description: ["", :HardJob],
      integration: ["backend", Module.new, Kernel],
      producer: ["yes", 1],
      report_retried_exception?: ["yes", 1]
    }.each do |hook, malformed_results|
      malformed_results.each do |malformed|
        it "logs and returns the fallback result when #{hook} returns #{malformed.inspect}" do
          extension = build_hooked_extension(hook => ->(**) { malformed })

          expect(call_hook(extension, hook)).to eq(fallback_results.fetch(hook))
          expect(string_io.string).to include("sidekiq", hook.to_s)
        end
      end
    end
  end
end
