module Sentry
  module Rails
    module Breadcrumb
      module ActiveSupportLogger
        ALLOWED_LIST = {
          # action_controller
          "write_fragment.action_controller" => %i[key],
          "read_fragment.action_controller" => %i[key],
          "exist_fragment?.action_controller" => %i[key],
          "expire_fragment.action_controller" => %i[key],
          "start_processing.action_controller" => %i[controller action params format method path],
          "process_action.action_controller" => %i[controller action params format method path status view_runtime db_runtime],
          "send_file.action_controller" => %i[path],
          "redirect_to.action_controller" => %i[status location],
          "halted_callback.action_controller" => %i[filter],
          # action_dispatch
          "process_middleware.action_dispatch" => %i[middleware],
          # action_view
          "render_template.action_view" => %i[identifier layout],
          "render_partial.action_view" => %i[identifier],
          "render_collection.action_view" => %i[identifier count cache_hits],
          "render_layout.action_view" => %i[identifier],
          # active_record
          "sql.active_record" => %i[sql name statement_name cached],
          "instantiation.active_record" => %i[record_count class_name],
          # action_mailer
          # not including to, from, or subject..etc. because of PII concern
          "deliver.action_mailer" => %i[mailer date perform_deliveries],
          "process.action_mailer" => %i[mailer action params],
          # active_support
          "cache_read.active_support" => %i[key store hit],
          "cache_generate.active_support" => %i[key store],
          "cache_fetch_hit.active_support" => %i[key store],
          "cache_write.active_support" => %i[key store],
          "cache_delete.active_support" => %i[key store],
          "cache_exist?.active_support" => %i[key store],
          # active_job
          "enqueue_at.active_job" => %i[],
          "enqueue.active_job" => %i[],
          "enqueue_retry.active_job" => %i[],
          "perform_start.active_job" => %i[],
          "perform.active_job" => %i[],
          "retry_stopped.active_job" => %i[],
          "discard.active_job" => %i[],
          # action_cable
          "perform_action.action_cable" => %i[channel_class action],
          "transmit.action_cable" => %i[channel_class],
          "transmit_subscription_confirmation.action_cable" => %i[channel_class],
          "transmit_subscription_rejection.action_cable" => %i[channel_class],
          "broadcast.action_cable" => %i[broadcasting],
          # active_storage
          "service_upload.active_storage" => %i[service key checksum],
          "service_streaming_download.active_storage" => %i[service key],
          "service_download_chunk.active_storage" => %i[service key],
          "service_download.active_storage" => %i[service key],
          "service_delete.active_storage" => %i[service key],
          "service_delete_prefixed.active_storage" => %i[service prefix],
          "service_exist.active_storage" => %i[service key exist],
          "service_url.active_storage" => %i[service key url],
          "service_update_metadata.active_storage" => %i[service key],
          "preview.active_storage" => %i[key],
          "analyze.active_storage" => %i[analyzer],
        }.freeze

        class << self
          def add(name, started, _finished, _unique_id, data)
            # skip Rails' internal events
            return if name.start_with?("!")

            allowed_keys = ALLOWED_LIST[name]

            if data.is_a?(Hash)
              data = data.slice(*allowed_keys)
            end

            crumb = Sentry::Breadcrumb.new(
              data: data,
              category: name,
              timestamp: started.to_i
            )
            Sentry.add_breadcrumb(crumb)
          end

          def inject
            @subscriber = ::ActiveSupport::Notifications.subscribe(/.*/) do |name, started, finished, unique_id, data|
              # we only record events that has a started timestamp
              if started.is_a?(Time)
                add(name, started, finished, unique_id, data)
              end
            end
          end

          def detach
            ::ActiveSupport::Notifications.unsubscribe(@subscriber)
          end
        end
      end
    end
  end
end
