require 'test_helper'

class StacktraceInterfaceTest < Raven::Test
  def setup
    @frame = Raven::StacktraceInterface::Frame.new
    @frame.abs_path = Dir.pwd + "/test/support/test_file.rb"
  end

  it "has a nil filename if no absolute path" do
    @frame.abs_path = nil
    assert_nil @frame.filename
  end

  it "chops off project root prefix if under the root and an in_app frame" do
    @frame.project_root = Dir.pwd

    assert @frame.in_app
    assert_equal "test/support/test_file.rb", @frame.filename
  end

  it "project root prefix if we are under it but longest load path doesnt match" do
    @frame.project_root = Dir.pwd
    @frame.longest_load_path = nil
    @frame.abs_path = Dir.pwd + "/myfile.rb"

    refute @frame.in_app
    assert_equal "myfile.rb", @frame.filename
  end

  it "has no prefix chop if nothing matches" do
    assert_equal @frame.abs_path, @frame.filename
  end

  it "uses longest load path match if not under project root" do
    @frame.project_root = "/some/other"
    @frame.longest_load_path = Dir.pwd + "/test/support/"

    assert_equal "test_file.rb", @frame.filename
  end

  # Simulate a gem under project_root/vendor/bundle
  it "correctly deals with vendored gems" do
    @frame.project_root = Dir.pwd
    @frame.longest_load_path = Dir.pwd + "/vendor/bundle"
    @frame.abs_path = Dir.pwd + "/vendor/bundle/ruby/2.1.0/gems/activesupport-4.1.9/lib/active_support/callbacks.rb"

    refute @frame.in_app
    assert_equal "activesupport-4.1.9/lib/active_support/callbacks.rb", @frame.filename
  end

  # Simulate a rails engine under project_root
  it "correctly deals with Rails engines" do
    skip("This doesn't work ATM, see https://github.com/getsentry/raven-ruby/issues/614")
    # I think we will probably need multiple project roots.
    @frame.project_root = Dir.pwd
    @frame.longest_load_path = Dir.pwd + "/myengine"
    @frame.abs_path = Dir.pwd + "/myengine/app/models/user.rb"

    assert @frame.in_app
    assert_equal "myengine/app/models/user.rb", @frame.filename
  end
end
