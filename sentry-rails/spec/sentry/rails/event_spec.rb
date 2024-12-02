# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::Event do
  before do
    make_basic_app
  end

  it "sets right SDK information" do
    event_hash = Sentry::Rails.capture_message("foo").to_hash

    expect(event_hash[:sdk]).to eq(name: "sentry.ruby.rails", version: Sentry::Rails::VERSION)
  end

  context 'with an application stacktrace' do
    let(:exception) do
      e = Exception.new("Oh no!")
      allow(e).to receive(:backtrace).and_return [
        "#{Rails.root}/vendor/bundle/cache/other_gem.rb:10:in `public_method'",
        "vendor/bundle/some_gem.rb:10:in `a_method'",
        "#{Rails.root}/app/models/user.rb:132:in `new_function'",
        "/gem/lib/path:87:in `a_function'",
        "/app/some/other/path:1412:in `other_function'",
        "test/some/other/path:1412:in `other_function'"
      ]
      e
    end

    let(:hash) { Sentry::Rails.capture_exception(exception).to_hash }

    it 'marks in_app correctly' do
      frames = hash[:exception][:values][0][:stacktrace][:frames]
      expect(frames[0][:filename]).to eq("test/some/other/path")
      expect(frames[0][:abs_path]).to eq("test/some/other/path")
      expect(frames[0][:in_app]).to eq(true)
      expect(frames[1][:filename]).to eq("/app/some/other/path")
      expect(frames[1][:in_app]).to eq(false)
      expect(frames[2][:filename]).to eq("/gem/lib/path")
      expect(frames[2][:in_app]).to eq(false)
      expect(frames[3][:filename]).to eq("app/models/user.rb")
      expect(frames[3][:in_app]).to eq(true)
      expect(frames[4][:filename]).to eq("vendor/bundle/some_gem.rb")
      expect(frames[4][:in_app]).to eq(false)
      expect(frames[5][:filename]).to eq("dummy/test_rails_app/vendor/bundle/cache/other_gem.rb")
      expect(frames[5][:in_app]).to eq(false)
    end

    context 'when an in_app path under project_root is on the load path' do
      it 'normalizes the filename using project_root' do
        $LOAD_PATH << "#{Rails.root}/app/models"
        frames = hash[:exception][:values][0][:stacktrace][:frames]
        expect(frames[3][:filename]).to eq("app/models/user.rb")
        expect(frames[3][:abs_path]).to eq("#{Rails.root}/app/models/user.rb")
        $LOAD_PATH.delete("#{Rails.root}/app/models")
      end
    end

    context 'when a non-in_app path under project_root is on the load path' do
      it 'normalizes the filename using the load path' do
        $LOAD_PATH.push "vendor/bundle"
        frames = hash[:exception][:values][0][:stacktrace][:frames]
        expect(frames[5][:filename]).to eq("dummy/test_rails_app/vendor/bundle/cache/other_gem.rb")
        expect(frames[5][:abs_path]).to eq("#{Rails.root}/vendor/bundle/cache/other_gem.rb")
        $LOAD_PATH.pop
      end
    end

    context "when a non-in_app path under project_root isn't on the load path" do
      it 'normalizes the filename using project_root' do
        frames = hash[:exception][:values][0][:stacktrace][:frames]
        expect(frames[5][:filename]).to eq("dummy/test_rails_app/vendor/bundle/cache/other_gem.rb")
        expect(frames[5][:abs_path]).to eq("#{Rails.root}/vendor/bundle/cache/other_gem.rb")
      end
    end
  end
end
