require "spec_helper"

RSpec.describe "with uninitialized SDK" do
  before do
    # completely nuke any initialized hubs
    Sentry.instance_variable_set(:@main_hub, nil)
    expect(Sentry.initialized?).to eq(false)
  end

  it { expect(Sentry.configuration).to eq(nil) }
  it { expect(Sentry.send_event(nil)).to eq(nil) }
  it { expect(Sentry.capture_exception(Exception.new)).to eq(nil) }
  it { expect(Sentry.capture_message("foo")).to eq(nil) }
  it { expect(Sentry.capture_event(nil)).to eq(nil) }
  it { expect(Sentry.set_tags(foo: "bar")).to eq(nil) }
  it { expect(Sentry.set_user(name: "John")).to eq(nil) }
  it { expect(Sentry.set_extras(foo: "bar")).to eq(nil) }
  it { expect(Sentry.set_context(foo:  { bar: "baz" })).to eq(nil) }
  it { expect(Sentry.last_event_id).to eq(nil) }
  it { expect(Sentry.exception_captured?(Exception.new)).to eq(false) }
  it do
    expect { Sentry.configure_scope { raise "foo" } }.not_to raise_error(RuntimeError)
  end

  it do
    expect { Sentry.with_exception_captured { raise "foo" } }.to raise_error(RuntimeError)
  end

  it do
    result = Sentry.with_child_span { |span| "foo" }
    expect(result).to eq("foo")
  end

  it do
    result = Sentry.with_scope { |scope| "foo" }
    expect(result).to eq("foo")
  end

  it do
    result = Sentry.with_session_tracking { |scope| "foo" }
    expect(result).to eq("foo")
  end
end

