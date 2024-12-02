# frozen_string_literal: true

if defined?(ActionCable) && ActionCable.version >= Gem::Version.new('6.0.0')
  require "spec_helper"
  require "action_cable/engine"

  ::ActionCable.server.config.cable = { "adapter" => "test" }

  class ChatChannel < ::ActionCable::Channel::Base
    def subscribed
      raise "foo"
    end
  end

  class ContentChannel < ::ActionCable::Channel::Base
    def content
      "value"
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

  class FailToOpenConnection < ActionCable::Connection::Base
    def connect
      raise "foo"
    end
  end

  class FailToCloseConnection < ActionCable::Connection::Base
    def disconnect
      raise "bar"
    end
  end

  RSpec.describe "without Sentry initialized" do
    before do
      allow(Sentry).to receive(:get_main_hub).and_return(nil)
      make_basic_app
      Sentry.clone_hub_to_current_thread # make sure the thread doesn't set a hub
    end

    describe ChatChannel, type: :channel do
      it "doesn't swallow the app's operation" do
        expect { subscribe }.to raise_error('foo')
      end
    end

    describe ContentChannel, type: :channel do
      let(:connection) do
        env = Rack::MockRequest.env_for "/test", "HTTP_CONNECTION" => "upgrade", "HTTP_UPGRADE" => "websocket",
          "HTTP_HOST" => "localhost", "HTTP_ORIGIN" => "http://rubyonrails.com"
        described_class.new(spy, env)
      end

      it "perform_action returns content" do
        expect(connection.perform_action({ "action" => "content" })).to eq("value")
      end
    end
  end

  RSpec.describe "Sentry::Rails::ActionCableExtensions", type: :channel do
    let(:transport) { Sentry.get_current_client.transport }

    after do
      transport.events = []
    end

    describe "Connection" do
      before do
        make_basic_app
      end

      let(:connection) do
        env = Rack::MockRequest.env_for "/test", "HTTP_CONNECTION" => "upgrade", "HTTP_UPGRADE" => "websocket",
          "HTTP_HOST" => "localhost", "HTTP_ORIGIN" => "http://rubyonrails.com"
        described_class.new(spy, env)
      end

      before do
        connection.process
      end

      describe FailToOpenConnection do
        it "captures errors happen when establishing connection" do
          expect { connection.send(:handle_open) }.to raise_error(RuntimeError, "foo")

          expect(transport.events.count).to eq(1)

          event = transport.events.last.to_json_compatible
          expect(event["transaction"]).to eq("FailToOpenConnection#connect")
          expect(event["transaction_info"]).to eq({ "source" => "view" })
        end
      end

      describe FailToCloseConnection do
        it "captures errors happen when establishing connection" do
          connection.send(:handle_open)

          expect { connection.send(:handle_close) }.to raise_error(RuntimeError, "bar")

          expect(transport.events.count).to eq(1)

          event = transport.events.last.to_json_compatible
          expect(event["transaction"]).to eq("FailToCloseConnection#disconnect")
          expect(event["transaction_info"]).to eq({ "source" => "view" })
        end
      end
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
          expect(event["transaction"]).to eq("ChatChannel#subscribed")
          expect(event["transaction_info"]).to eq({ "source" => "view" })
          expect(event["contexts"]).to include("action_cable" => { "params" => { "room_id" => 42 } })
        end
      end

      describe ContentChannel do
        before { subscribe }

        it "perform_action returns content" do
          expect(perform :content, foo: 'bar').to eq("value")
        end
      end

      describe AppearanceChannel do
        before { subscribe room_id: 42 }

        it "captures errors during the action" do
          expect { perform :appear, foo: 'bar' }.to raise_error('foo')
          expect(transport.events.count).to eq(1)

          event = transport.events.last.to_json_compatible

          expect(event["transaction"]).to eq("AppearanceChannel#appear")
          expect(event["transaction_info"]).to eq({ "source" => "view" })
          expect(event["contexts"]).to include(
            "action_cable" => {
              "params" => { "room_id" => 42 },
              "data" => { "action" => "appear", "foo" => "bar" }
            }
          )
        end

        it "captures errors during unsubscribe" do
          expect { unsubscribe }.to raise_error('foo')
          expect(transport.events.count).to eq(1)

          event = transport.events.last.to_json_compatible

          expect(event["transaction"]).to eq("AppearanceChannel#unsubscribed")
          expect(event["transaction_info"]).to eq({ "source" => "view" })
          expect(event["contexts"]).to include(
            "action_cable" => {
              "params" => { "room_id" => 42 }
            }
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

          expect(event["transaction"]).to eq("ChatChannel#subscribed")
          expect(event["contexts"]).to include("action_cable" => { "params" => { "room_id" => 42 } })

          transaction = transport.events.last.to_json_compatible

          expect(transaction["type"]).to eq("transaction")
          expect(transaction["transaction"]).to eq("ChatChannel#subscribed")
          expect(transaction["transaction_info"]).to eq({ "source" => "view" })
          expect(transaction["contexts"]).to include(
            "action_cable" => {
              "params" => { "room_id" => 42 }
            }
          )
          expect(transaction["contexts"]).to include(
            "trace" => hash_including(
              "op" => "websocket.server",
              "status" => "internal_error",
              "origin" => "auto.http.rails.actioncable"
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

          expect(subscription_transaction["type"]).to eq("transaction")
          expect(subscription_transaction["transaction"]).to eq("AppearanceChannel#subscribed")
          expect(subscription_transaction["transaction_info"]).to eq({ "source" => "view" })
          expect(subscription_transaction["contexts"]).to include(
            "action_cable" => {
              "params" => { "room_id" => 42 }
            }
          )
          expect(subscription_transaction["contexts"]).to include(
            "trace" => hash_including(
              "op" => "websocket.server",
              "status" => "ok",
              "origin" => "auto.http.rails.actioncable"
            )
          )

          event = transport.events[1].to_json_compatible

          expect(event["transaction"]).to eq("AppearanceChannel#appear")
          expect(event["transaction_info"]).to eq({ "source" => "view" })
          expect(event["contexts"]).to include(
            "action_cable" => {
              "params" => { "room_id" => 42 },
              "data" => { "action" => "appear", "foo" => "bar" }
            }
          )

          action_transaction = transport.events[2].to_json_compatible

          expect(action_transaction["type"]).to eq("transaction")
          expect(action_transaction["transaction"]).to eq("AppearanceChannel#appear")
          expect(action_transaction["transaction_info"]).to eq({ "source" => "view" })
          expect(action_transaction["contexts"]).to include(
            "action_cable" => {
              "params" => { "room_id" => 42 },
              "data" => { "action" => "appear", "foo" => "bar" }
            }
          )
          expect(action_transaction["contexts"]).to include(
            "trace" => hash_including(
              "op" => "websocket.server",
              "status" => "internal_error",
              "origin" => "auto.http.rails.actioncable"
            )
          )
        end

        it "captures errors during unsubscribe" do
          expect { unsubscribe }.to raise_error('foo')
          expect(transport.events.count).to eq(3)

          subscription_transaction = transport.events[0].to_json_compatible

          expect(subscription_transaction["type"]).to eq("transaction")
          expect(subscription_transaction["transaction"]).to eq("AppearanceChannel#subscribed")
          expect(subscription_transaction["transaction_info"]).to eq({ "source" => "view" })
          expect(subscription_transaction["contexts"]).to include(
            "action_cable" => {
              "params" => { "room_id" => 42 }
            }
          )
          expect(subscription_transaction["contexts"]).to include(
            "trace" => hash_including(
              "op" => "websocket.server",
              "status" => "ok",
              "origin" => "auto.http.rails.actioncable"
            )
          )

          event = transport.events[1].to_json_compatible

          expect(event["transaction"]).to eq("AppearanceChannel#unsubscribed")
          expect(event["transaction_info"]).to eq({ "source" => "view" })
          expect(event["contexts"]).to include(
            "action_cable" => {
              "params" => { "room_id" => 42 }
            }
          )

          transaction = transport.events[2].to_json_compatible

          expect(transaction["type"]).to eq("transaction")
          expect(transaction["transaction"]).to eq("AppearanceChannel#unsubscribed")
          expect(transaction["transaction_info"]).to eq({ "source" => "view" })
          expect(transaction["contexts"]).to include(
            "action_cable" => {
              "params" => { "room_id" => 42 }
            }
          )
          expect(transaction["contexts"]).to include(
            "trace" => hash_including(
              "op" => "websocket.server",
              "status" => "internal_error",
              "origin" => "auto.http.rails.actioncable"
            )
          )
        end
      end
    end
  end
end
