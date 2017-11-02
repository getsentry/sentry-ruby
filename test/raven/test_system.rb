require 'test_helper'

class TestSystem < Raven::Test
  def setup
    @sys = Raven::System.new
  end

  it "executes system commands, stripping output" do
    # normally this command returns "hello\n"
    assert_equal "hello", @sys.command("echo hello")
  end

  it "returns nil if command fails" do
    assert_nil @sys.command("ls --fail")
  end

  it "returns nil if no result" do
    assert_nil @sys.command("echo")
  end

  it "reads cap revision files of old type" do
    assert_equal "cf8734ece3938fc67262ad5e0d4336f820689307", @sys.cap_revision(Dir.pwd + "/test/support/cap_oldstyle")
  end

  it "reads cap revision files of new type" do
    assert_equal "20140308001458", @sys.cap_revision(Dir.pwd + "/test/support/cap_newstyle")
  end

  it "pulls from Heroku env for servername" do
    def @sys.running_on_heroku?; true; end

    def @sys.env; { "DYNO" => "web.1" }; end

    assert_equal "web.1", @sys.server_name
  end

  it "grabs current environment from env" do
    def @sys.env; {}; end
    assert_equal "default", @sys.current_environment
  end

  it "prefers rack env next" do
    def @sys.env; { "RACK_ENV" => "env" }; end
    assert_equal "env", @sys.current_environment
  end

  it "prefers rails env next" do
    def @sys.env; { "RACK_ENV" => "env", "RAILS_ENV" => "env1" }; end
    assert_equal "env1", @sys.current_environment
  end

  it "prefers SENTRY_CURRENT_ENV first" do
    def @sys.env; { "RAILS_ENV" => "env1", "SENTRY_CURRENT_ENV" => "env2" }; end
    assert_equal "env2", @sys.current_environment
  end
end
