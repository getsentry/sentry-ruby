# frozen_string_literal: true

RSpec.shared_examples "parameter filtering" do |subscriber_class|
  let(:test_instance) { subscriber_class.new }

  describe "#filter_sensitive_params" do
    around do |example|
      original_filter_params = Rails.application.config.filter_parameters.dup

      Rails.application.config.filter_parameters.concat([
        :password, :secret, :custom_secret, :api_key,
        :credit_card, :authorization, :token, :session_token
      ]).uniq!

      example.run

      Rails.application.config.filter_parameters = original_filter_params
    end

    context "when params is not a hash" do
      it "returns empty hash for nil" do
        result = test_instance.filter_sensitive_params(nil)
        expect(result).to eq({})
      end

      it "returns empty hash for non-hash objects" do
        result = test_instance.filter_sensitive_params("not a hash")
        expect(result).to eq({})
      end

      it "returns empty hash for arrays" do
        result = test_instance.filter_sensitive_params([1, 2, 3])
        expect(result).to eq({})
      end
    end

    context "when params is a valid hash" do
      it "preserves non-sensitive parameters" do
        params = {
          "name" => "John Doe",
          "email" => "john@example.com",
          "age" => 30,
          "preferences" => { "theme" => "dark" }
        }

        result = test_instance.filter_sensitive_params(params)

        expect(result).to include("name" => "John Doe")
        expect(result).to include("email" => "john@example.com")
        expect(result).to include("age" => 30)
        expect(result).to include("preferences" => { "theme" => "dark" })
      end

      it "filters default sensitive parameters" do
        params = {
          "name" => "John Doe",
          "password" => "secret123",
          "password_confirmation" => "secret123",
          "normal_param" => "safe_value"
        }

        result = test_instance.filter_sensitive_params(params)

        expect(result).to include("name" => "John Doe")
        expect(result).to include("normal_param" => "safe_value")
        expect(result).to include("password" => "[FILTERED]")
        expect(result).to include("password_confirmation" => "[FILTERED]")
      end

      it "filters custom configured sensitive parameters" do
        params = {
          "name" => "John Doe",
          "custom_secret" => "top_secret",
          "api_key" => "abc123xyz",
          "credit_card" => "1234-5678-9012-3456",
          "authorization" => "Bearer token123",
          "normal_param" => "safe_value"
        }

        result = test_instance.filter_sensitive_params(params)

        expect(result).to include("name" => "John Doe")
        expect(result).to include("normal_param" => "safe_value")
        expect(result).to include("custom_secret" => "[FILTERED]")
        expect(result).to include("api_key" => "[FILTERED]")
        expect(result).to include("credit_card" => "[FILTERED]")
        expect(result).to include("authorization" => "[FILTERED]")
      end

      it "handles mixed sensitive and non-sensitive parameters" do
        params = {
          "user_id" => 123,
          "username" => "johndoe",
          "password" => "secret",
          "session_token" => "abc123",
          "preferences" => {
            "notifications" => true,
            "api_key" => "sensitive_key"
          }
        }

        result = test_instance.filter_sensitive_params(params)

        expect(result).to include("user_id" => 123)
        expect(result).to include("username" => "johndoe")
        expect(result).to include("password" => "[FILTERED]")
        expect(result).to include("session_token" => "[FILTERED]")
        expect(result).to have_key("preferences")
      end

      it "returns a new hash and doesn't modify the original" do
        original_params = {
          "name" => "John",
          "password" => "secret"
        }
        original_copy = original_params.dup

        result = test_instance.filter_sensitive_params(original_params)

        expect(original_params).to eq(original_copy)
        expect(result).not_to equal(original_params)
      end

      it "handles empty hash" do
        result = test_instance.filter_sensitive_params({})
        expect(result).to eq({})
      end
    end

    context "with Rails filter_parameters configuration" do
      it "respects dynamically added filter parameters" do
        original_filter_params = Rails.application.config.filter_parameters.dup

        begin
          Rails.application.config.filter_parameters += [:dynamic_secret]

          params = {
            "name" => "John",
            "dynamic_secret" => "should_be_filtered",
            "normal_param" => "value"
          }

          result = test_instance.filter_sensitive_params(params)

          expect(result).to include("name" => "John")
          expect(result).to include("normal_param" => "value")
          expect(result).to include("dynamic_secret" => "[FILTERED]")
        ensure
          Rails.application.config.filter_parameters = original_filter_params
        end
      end
    end
  end
end
