# frozen_string_literal: true

RSpec.describe Sentry::BreadcrumbBuffer do
  before do
    perform_basic_setup
  end

  let(:crumb_1) do
    Sentry::Breadcrumb.new(
      category: "foo",
      message: "crumb_1",
      data: {
        name: "John",
        age: 25
      }
    )
  end

  let(:crumb_2) do
    Sentry::Breadcrumb.new(
      category: "bar",
      message: "crumb_2",
    )
  end

  describe "#record" do
    subject do
      described_class.new(1)
    end

    it "doesn't exceed the size limit" do
      subject.record(crumb_1)

      expect(subject.buffer.size).to eq(1)

      subject.record(crumb_2)

      expect(subject.buffer.size).to eq(1)

      expect(subject.peek).to eq(crumb_2)
    end
  end

  describe "#to_h" do
    it "serializes breadcrumbs" do
      subject.record(crumb_1)
      subject.record(crumb_2)

      result = subject.to_h[:values]

      expect(result[0][:category]).to eq("foo")
      expect(result[0][:data]).to eq({ name: "John", age: 25 })
      expect(result[1][:category]).to eq("bar")
    end
  end
end
