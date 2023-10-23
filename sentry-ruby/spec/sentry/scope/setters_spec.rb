require "spec_helper"

RSpec.describe Sentry::Scope do
  let(:new_breadcrumb) do
    new_breadcrumb = Sentry::Breadcrumb.new
    new_breadcrumb.message = "foo"
    new_breadcrumb
  end

  describe "#set_rack_env", rack: true do
    let(:env) do
      Rack::MockRequest.env_for("/test", {})
    end
    it "sets the rack env" do
      subject.set_rack_env(env)

      expect(subject.rack_env).to eq(env)
    end
    it "sets empty hash when the env is nil" do
      subject.set_rack_env({})

      expect(subject.rack_env).to eq({})
    end
  end

  describe "#set_span" do
    let(:transaction) do
      client = Sentry::Client.new(Sentry::Configuration.new)
      hub = Sentry::Hub.new(client, subject)
      Sentry::Transaction.new(name: "test transaction", hub: hub)
    end

    let(:span) { Sentry::Span.new(op: "foo", transaction: transaction) }

    it "sets the Span" do
      subject.set_span(span)

      expect(subject.span).to eq(span)
    end

    it "sets the Transaction" do
      subject.set_span(transaction)

      expect(subject.span).to eq(transaction)
    end

    it "raises error when passed non-Span argument" do
      expect do
        subject.set_span(1)
      end.to raise_error(ArgumentError)
    end
  end

  describe "#set_user" do
    it "raises error when passed non-hash argument" do
      expect do
        subject.set_user(1)
      end.to raise_error(ArgumentError)
    end

    it "sets the user" do
      subject.set_user({id: 1, name: "Jack"})

      expect(subject.user).to eq({id: 1, name: "Jack"})
    end

    it "unsets user when given empty data" do
      subject.set_user({id: 1, name: "Jack"})

      subject.set_user({})

      expect(subject.user).to eq({})
    end
  end

  describe "#set_extras" do
    it "raises error when passed non-hash argument" do
      expect do
        subject.set_extras(1)
      end.to raise_error(ArgumentError)
    end

    it "merges the extras" do
      subject.set_extras({bar: "baz"})
      expect(subject.extra).to eq({bar: "baz"})

      subject.set_extras({foo: "bar"})
      expect(subject.extra).to eq({bar: "baz", foo: "bar"})
    end
  end

  describe "#set_extra" do
    it "merges the key value with existing extra" do
      subject.set_extras({bar: "baz"})

      subject.set_extra(:foo, "bar")

      expect(subject.extra).to eq({foo: "bar", bar: "baz"})
    end
  end

  describe "#set_contexts" do
    it "raises error when passed non-hash argument" do
      expect do
        subject.set_contexts(1)
      end.to raise_error(ArgumentError)
    end

    it "raises error when passed non-hash context value" do
      expect do
        subject.set_contexts({ character: "John" })
      end.to raise_error(ArgumentError)
    end

    it "merges the context hash" do
      subject.set_contexts({ character: { name: "John" }})
      expect(subject.contexts).to include({ character: { name: "John" }})

      subject.set_contexts({ character: { name: "John", age: 25 }})
      subject.set_contexts({ another_character: { name: "Jane", age: 20 }})
      expect(subject.contexts).to include({ character: { name: "John", age: 25 }})
      expect(subject.contexts).to include({ another_character: { name: "Jane", age: 20 }})
    end

    it "merges context with the same key" do
      subject.set_contexts({ character: { name: "John" }})
      subject.set_contexts({ character: { age: 25 }})
      expect(subject.contexts).to include({ character: { name: "John", age: 25 }})
    end

    it "allows overwriting old values" do
      subject.set_contexts({ character: { name: "John" }})
      subject.set_contexts({ character: { name: "Jimmy" }})
      expect(subject.contexts).to include({ character: { name: "Jimmy" }})
    end
  end

  describe "#set_context" do
    it "raises error when passed non-hash value" do
      expect do
        subject.set_context(:character, "John")
      end.to raise_error(ArgumentError)
    end

    it "merges the key value with existing context" do
      subject.set_context(:character, { name: "John" })
      expect(subject.contexts).to include({ character: { name: "John" }})

      subject.set_context(:character, { name: "John", age: 25 })
      expect(subject.contexts).to include({ character: { name: "John", age: 25 }})

      subject.set_context(:another_character, { name: "Jane", age: 20 })
      expect(subject.contexts).to include(
        {
          character: { name: "John", age: 25 },
          another_character: { name: "Jane", age: 20 }
        }
      )
    end

    it "merges context with the same key" do
      subject.set_context(:character, { name: "John" })
      subject.set_context(:character, { age: 25 })
      expect(subject.contexts).to include({ character: { name: "John", age: 25 }})
    end

    it "allows overwriting old values" do
      subject.set_context(:character, { name: "John" })
      subject.set_context(:character, { name: "Jimmy" })
      expect(subject.contexts).to include({ character: { name: "Jimmy" }})
    end
  end

  describe "#set_tags" do
    it "raises error when passed non-hash argument" do
      expect do
        subject.set_tags(1)
      end.to raise_error(ArgumentError)
    end

    it "merges tags" do
      subject.set_tags({bar: "baz"})
      expect(subject.tags).to eq({bar: "baz"})

      subject.set_tags({foo: "bar"})
      expect(subject.tags).to eq({bar: "baz", foo: "bar"})
    end
  end

  describe "#set_tag" do
    it "merges the key value with existing tag" do
      subject.set_tags({bar: "baz"})

      subject.set_tag(:foo, "bar")

      expect(subject.tags).to eq({foo: "bar", bar: "baz"})
    end
  end

  describe "#set_level" do
    it "sets the scope's level" do
      subject.set_level(:info)

      expect(subject.level).to eq(:info)
    end
  end

  describe "#set_transaction_name" do
    it "pushes the transaction_name to transaction_names stack" do
      subject.set_transaction_name("WelcomeController#home")

      expect(subject.transaction_name).to eq("WelcomeController#home")
    end
  end

  describe "#set_fingerprint" do
    it "replaces the fingerprint" do
      subject.set_fingerprint(["foo"])

      expect(subject.fingerprint).to eq(["foo"])

      subject.set_fingerprint(["bar"])

      expect(subject.fingerprint).to eq(["bar"])
    end
  end
end
