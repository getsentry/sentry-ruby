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

    after do
      transport.events = []
    end

    context "without tracing" do
      before do
        make_basic_app
      end

      describe ChatChannel do
        it "captures errors during the subscribe" do
          expect { subscribe room_id: 42 }.to raise_error('foo')
          expect(transport.events.count).to eq(1)

          event = transport.events.last.to_json_compatible
          expect(event).to include(
            "transaction" => "ChatChannel#subscribed",
            "contexts" => hash_including(
              "action_cable" => {
                "params" => { "room_id" => 42 }
              }
            )
          )
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
            "contexts" => hash_including(
              "action_cable" => {
                "params" => { "room_id" => 42 },
                "data" => { "action" => "appear", "foo" => "bar" }
              }
            )
          )
        end

        it "captures errors during unsubscribe" do
          expect { unsubscribe }.to raise_error('foo')
          expect(transport.events.count).to eq(1)

          event = transport.events.last.to_json_compatible

          expect(event).to include(
            "transaction" => "AppearanceChannel#unsubscribed",
            "contexts" => hash_including(
              "action_cable" => {
                "params" => { "room_id" => 42 }
              }
            )
          )
        end
      end
    end

    context "with tracing enabled" do
      before do
        make_basic_app do |config|
          config.traces_sample_rate = 1.0
        end
      end

      describe ChatChannel do
        it "captures errors and transactions during the subscribe" do
          expect { subscribe room_id: 42 }.to raise_error('foo')
          expect(transport.events.count).to eq(2)

          event = transport.events.first.to_json_compatible

          expect(event).to include(
            "transaction" => "ChatChannel#subscribed",
            "contexts" => hash_including(
              "action_cable" => {
                "params" => { "room_id" => 42 }
              }
            )
          )

          transaction = transport.events.last.to_json_compatible

          expect(transaction).to include(
            "type" => "transaction",
            "transaction" => "ChatChannel#subscribed",
            "contexts" => hash_including(
              "action_cable" => {
                "params" => { "room_id" => 42 }
              },
              "trace" => hash_including(
                "op" => "rails.action_cable",
                "status" => "internal_error"
              )
            )
          )
        end
      end

      describe AppearanceChannel do
        before { subscribe room_id: 42 }

        it "captures errors and transactions during the action" do
          expect { perform :appear, foo: 'bar' }.to raise_error('foo')
          expect(transport.events.count).to eq(3)

          subscription_transaction = transport.events[0].to_json_compatible

          expect(subscription_transaction).to include(
            "type" => "transaction",
            "contexts" => hash_including(
              "trace" => hash_including(
                "op" => "rails.action_cable",
                "status" => "ok"
              ),
              "action_cable" => {
                "params" => { "room_id" => 42 }
              }
            ),
            "transaction" => "AppearanceChannel#subscribed"
          )

          event = transport.events[1].to_json_compatible

          expect(event).to include(
            "transaction" => "AppearanceChannel#appear",
            "contexts" => hash_including(
              "action_cable" => {
                "params" => { "room_id" => 42 },
                "data" => { "action" => "appear", "foo" => "bar" }
              }
            )
          )

          action_transaction = transport.events[2].to_json_compatible

          expect(action_transaction).to include(
            "type" => "transaction",
            "contexts" => hash_including(
              "trace" => hash_including(
                "op" => "rails.action_cable",
                "status" => "internal_error"
              ),
              "action_cable" => {
                "params" => { "room_id" => 42 },
                "data" => { "action" => "appear", "foo" => "bar" }
              }
            ),
            "transaction" => "AppearanceChannel#appear"
          )
        end

        it "captures errors during unsubscribe" do
          expect { unsubscribe }.to raise_error('foo')
          expect(transport.events.count).to eq(3)

          subscription_transaction = transport.events[0].to_json_compatible

          expect(subscription_transaction).to include(
            "type" => "transaction",
            "contexts" => hash_including(
              "trace" => hash_including(
                "op" => "rails.action_cable",
                "status" => "ok"
              ),
              "action_cable" => {
                "params" => { "room_id" => 42 }
              }
            ),
            "transaction" => "AppearanceChannel#subscribed"
          )

          event = transport.events[1].to_json_compatible

          expect(event).to include(
            "transaction" => "AppearanceChannel#unsubscribed",
            "contexts" => hash_including(
              "action_cable" => {
                "params" => { "room_id" => 42 }
              }
            )
          )

          transaction = transport.events[2].to_json_compatible

          expect(transaction).to include(
            "type" => "transaction",
            "contexts" => hash_including(
              "trace" => hash_including(
                "op" => "rails.action_cable",
                "status" => "internal_error"
              ),
              "action_cable" => {
                "params" => { "room_id" => 42 }
              }
            ),
            "transaction" => "AppearanceChannel#unsubscribed"
          )
        end
      end
    end
  end
end
