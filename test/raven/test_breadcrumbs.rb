require 'test_helper'

class RavenBreadcrumbsTest < Raven::Test
  def setup
    @breadcrumbs = Raven::BreadcrumbBuffer.new(10)
  end

  it "starts empty" do
    assert @breadcrumbs.empty?
  end

  it "records with a block" do
    @breadcrumbs.record do
      Raven::Breadcrumb.new.tap { |b| b.message = "test" }
    end

    assert_equal 1, @breadcrumbs.members.size
    refute @breadcrumbs.empty?
  end

  it "records breadcrumbs w/o block" do
    crumb = Raven::Breadcrumb.new.tap { |b| b.message = "test" }
    @breadcrumbs.record(crumb)

    assert_equal crumb, @breadcrumbs.members[0]
  end

  it "allows peeking" do
    assert_nil @breadcrumbs.peek

    crumb = Raven::Breadcrumb.new.tap { |b| b.message = "test" }
    @breadcrumbs.record(crumb)

    assert_equal crumb, @breadcrumbs.peek
  end

  it "is enumerable" do
    (0..10).each do |i|
      @breadcrumbs.record(Raven::Breadcrumb.new.tap { |b| b.message = i })
    end

    assert_kind_of Enumerator, @breadcrumbs.each
  end

  it "evicts when buffer exceeded" do
    (0..15).each do |i|
      @breadcrumbs.record(Raven::Breadcrumb.new.tap { |b| b.message = i })
    end

    assert_equal 6, @breadcrumbs.members[0].message
    assert_equal 15, @breadcrumbs.members[-1].message
  end

  it "converts to a hash" do
    crumb = Raven::Breadcrumb.new.tap { |b| b.message = "test" }
    @breadcrumbs.record(crumb)

    assert_equal [crumb.to_hash], @breadcrumbs.to_hash[:values]
  end

  it "clears in a threaded context" do
    crumb = Raven::Breadcrumb.new.tap { |b| b.message = "test" }
    Raven::BreadcrumbBuffer.current.record(crumb)
    Raven::BreadcrumbBuffer.clear!

    assert Raven::BreadcrumbBuffer.current.empty?
  end
end
