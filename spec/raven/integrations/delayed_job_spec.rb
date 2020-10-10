# frozen_string_literal: true

require 'spec_helper'
require 'delayed/backend/base'
require 'raven/integrations/delayed_job'

module Delayed
  module Plugins
    class Raven
      class SampleJob
        include Delayed::Backend::Base

        class << self
          def db_time_now
            Time.now
          end
        end

        attr_accessor :attempts, :created_at, :error, :handler, :id, :last_error, :locked_at, :locked_by,
                      :payload_object, :priority, :queue, :run_at

        def initialize
          super

          self.attempts = 0
        end

        def save!; end
      end

      class RaiseErrorPayload
        attr_accessor :job_data

        def perform
          raise 'error'
        end
      end
    end
  end
end

RSpec.describe Delayed::Plugins::Raven do
  let(:worker) { Delayed::Worker.new }

  context 'ActiveJob' do
    context 'when payload#perform raises exception' do
      let(:job) { Delayed::Plugins::Raven::SampleJob.new }

      before do
        allow(::Raven).to receive(:capture_exception)

        job.payload_object = Delayed::Plugins::Raven::RaiseErrorPayload.new

        worker.run(job)
      end

      it 'should capture exception' do
        expect(::Raven).to have_received(:capture_exception)
      end
    end
  end
end
