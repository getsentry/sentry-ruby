require 'spec_helper'

describe Raven::BreadcrumbBuffer do
  before(:each) do
    @breadcrumbs = Raven::BreadcrumbBuffer.new(10)
  end

  it "records breadcrumbs w/a block" do
    expect(@breadcrumbs.empty?).to be true

    @breadcrumbs.record do
      Raven::Breadcrumb.new.tap { |b| b.message = "test" }
    end

    expect(@breadcrumbs.members.size).to eq(1)
    expect(@breadcrumbs.empty?).to be false
  end

  it "records breadcrumbs w/o block" do
    crumb = Raven::Breadcrumb.new.tap { |b| b.message = "test" }
    @breadcrumbs.record(crumb)

    expect(@breadcrumbs.members[0]).to eq(crumb)
  end

  it "allows peeking" do
    expect(@breadcrumbs.peek).to eq(nil)

    crumb = Raven::Breadcrumb.new.tap { |b| b.message = "test" }
    @breadcrumbs.record(crumb)

    expect(@breadcrumbs.peek).to eq(crumb)
  end

  it "is enumerable" do
    (0..10).each do |i|
      @breadcrumbs.record(Raven::Breadcrumb.new.tap { |b| b.message = i })
    end

    expect(@breadcrumbs.each).to be_a Enumerator
  end

  it "evicts when buffer exceeded" do
    (0..10).each do |i|
      @breadcrumbs.record(Raven::Breadcrumb.new.tap { |b| b.message = i })
    end

    expect(@breadcrumbs.members[0].message).to eq(1)
    expect(@breadcrumbs.members[-1].message).to eq(10)
  end

  it "converts to a hash" do
    expect(@breadcrumbs.peek).to eq(nil)

    crumb = Raven::Breadcrumb.new.tap { |b| b.message = "test" }
    @breadcrumbs.record(crumb)

    expect(@breadcrumbs.to_hash[:values]).to eq([crumb.to_hash])
  end

  it "clears in a threaded context" do
    crumb = Raven::Breadcrumb.new.tap { |b| b.message = "test" }
    Raven::BreadcrumbBuffer.current.record(crumb)
    Raven::BreadcrumbBuffer.clear!

    expect(Raven::BreadcrumbBuffer.current.empty?).to be true
  end
end
