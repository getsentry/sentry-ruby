if defined?(ActionCable) && ActionCable.version >= Gem::Version.new('6.0.0')
  require "spec_helper"
  require "action_cable/engine"

  ::ActionCable.server.config.cable = { "adapter" => "test" }

  # ensure we can access `connection.env` in tests like we can in production
  ActiveSupport.on_load :action_cable_channel_test_case do
    class ::ActionCable::Channel::ConnectionStub
      def env
        @_env ||= ::ActionCable::Connection::TestRequest.create.env
      end
    end
  end

  class ChatChannel < ::ActionCable::Channel::Base
    def subscribed
      raise "foo"
    end
  end

  class AppearanceChannel < ::ActionCable::Channel::Base
    def appear
      raise "foo"
    end

    def unsubscribed
      raise "foo"
    end
  end

  RSpec.describe "Sentry::Rails::ActionCableExtensions", type: :channel do
    let(:transport) { Sentry.get_current_client.transport }

    before do
      make_basic_app
    end

    after do
      transport.events = []
    end

    describe ChatChannel do
      it "captures errors during the subscribe" do
        expect { subscribe room_id: 42 }.to raise_error('foo')
        expect(transport.events.count).to eq(1)

        event = transport.events.last.to_json_compatible

        expect(event).to include(
          "transaction" => "ChatChannel#subscribed",
          "extra" => {
            "action_cable" => {
              "params" => { "room_id" => 42 }
            }
          }
        )

        expect(Sentry.get_current_scope.extra).to eq({})
      end
    end

    describe AppearanceChannel do
      before { subscribe room_id: 42 }

      it "captures errors during the action" do
        expect { perform :appear, foo: 'bar' }.to raise_error('foo')
        expect(transport.events.count).to eq(1)

        event = transport.events.last.to_json_compatible

        expect(event).to include(
          "transaction" => "AppearanceChannel#appear",
          "extra" => {
            "action_cable" => {
              "params" => { "room_id" => 42 },
              "data" => { "action" => "appear", "foo" => "bar" }
            }
          }
        )

        expect(Sentry.get_current_scope.extra).to eq({})
      end

      it "captures errors during unsubscribe" do
        expect { unsubscribe }.to raise_error('foo')
        expect(transport.events.count).to eq(1)

        event = transport.events.last.to_json_compatible

        expect(event).to include(
          "transaction" => "AppearanceChannel#unsubscribed",
          "extra" => {
            "action_cable" => {
              "params" => { "room_id" => 42 }
            }
          }
        )

        expect(Sentry.get_current_scope.extra).to eq({})
      end
    end
  end
end
