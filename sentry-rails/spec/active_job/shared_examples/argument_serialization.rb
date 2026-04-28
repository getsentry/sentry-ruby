# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that serializes complex arguments" do
  let(:failing_job) do
    job_fixture do
      def perform(*_args, **_kwargs)
        raise "boom from argument_serialization spec"
      end
    end
  end

  def event_arguments
    last_sentry_event.extra[:arguments]
  end

  it "serializes ActiveRecord arguments via global id" do
    post = Post.create!

    expect do
      failing_job.perform_later(post)
      drain
    end.to raise_error(RuntimeError, /boom from argument_serialization spec/)

    expect(event_arguments).to eq([post.to_global_id.to_s])
  end

  it "recursively serializes nested hashes containing global ids" do
    post = Post.create!

    expect do
      failing_job.perform_later(wrapper: { post: post })
      drain
    end.to raise_error(RuntimeError, /boom from argument_serialization spec/)

    expect(event_arguments).to eq([{ wrapper: { post: post.to_global_id.to_s } }])
  end

  it "expands integer ranges into arrays", skip: RAILS_VERSION < 7.0 do
    expect do
      failing_job.perform_later(1..3)
      drain
    end.to raise_error(RuntimeError, /boom from argument_serialization spec/)

    expect(event_arguments).to eq([[1, 2, 3]])
  end

  it "stringifies ActiveSupport::TimeWithZone ranges preserving the boundary operator", skip: RAILS_VERSION < 7.0 do
    range = 1.day.ago...Time.zone.now

    expect do
      failing_job.perform_later(range)
      drain
    end.to raise_error(RuntimeError, /boom from argument_serialization spec/)

    serialized = event_arguments.first
    expect(serialized).to be_a(String)
    expect(serialized).to eq("#{range.first}...#{range.last}")
  end

  it "falls back to the original argument when to_global_id raises" do
    post = Post.create!

    problematic_job = job_fixture do
      define_method(:perform) do |passed_post|
        def passed_post.to_global_id
          raise "intentional"
        end

        raise "boom from argument_serialization spec"
      end
    end

    expect do
      problematic_job.perform_later(post)
      drain
    end.to raise_error(RuntimeError, /boom from argument_serialization spec/)

    expect(event_arguments).to eq([post])
  end

  it "passes through objects that do not respond to to_global_id unchanged" do
    mod = Module.new

    module_job = job_fixture do
      define_method(:perform) do |_mod|
        raise "boom from argument_serialization spec"
      end
    end

    expect do
      module_job.perform_now(mod)
    end.to raise_error(RuntimeError, /boom from argument_serialization spec/)

    expect(event_arguments).to eq([mod])
  end
end
