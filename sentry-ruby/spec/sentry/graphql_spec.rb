# frozen_string_literal: true

require 'spec_helper'

with_graphql = begin
                 require 'graphql'
                 true
               rescue LoadError
                 false
               end

RSpec.describe 'GraphQL' do
  it 'adds the graphql patch to registered patches' do
    expect(Sentry.registered_patches.keys).to include(:graphql)
  end

  context 'when patch enabled' do
    if with_graphql
      describe 'with graphql gem' do
        class Thing < GraphQL::Schema::Object
          field :str, String
          def str; 'blah'; end
        end

        class Query < GraphQL::Schema::Object
          field :int, Integer, null: false
          def int; 1; end

          field :thing, Thing
          def thing; :thing; end
        end

        class MySchema < GraphQL::Schema
          query(Query)
        end

        before do
          perform_basic_setup do |config|
            config.traces_sample_rate = 1.0
            config.enabled_patches << :graphql
          end
        end

        it 'enables the sentry tracer' do
          expect(MySchema.trace_modules_for(:default)).to include(::GraphQL::Tracing::SentryTrace)
        end

        it 'adds graphql spans to the transaction' do
          transaction = Sentry.start_transaction
          Sentry.get_current_scope.set_span(transaction)
          MySchema.execute('query foobar { int thing { str } }')
          transaction.finish

          expect(last_sentry_event.transaction).to eq('GraphQL/query.foobar')

          execute_span = last_sentry_event.spans.find { |s| s[:op] == 'graphql.execute' }
          expect(execute_span[:description]).to eq('query foobar')
          expect(execute_span[:data]).to eq({
            'graphql.document'=>'query foobar { int thing { str } }',
            'graphql.operation.name'=>'foobar',
            'graphql.operation.type'=>'query'
          })
        end
      end
    else
      describe 'without graphql gem' do
        it 'logs warning' do
          string_io = StringIO.new

          perform_basic_setup do |config|
            config.enabled_patches << :graphql
            config.logger = Logger.new(string_io)
          end

          expect(string_io.string).to include('WARN -- sentry: You tried to enable the GraphQL integration but no GraphQL gem was detected. Make sure you have the `graphql` gem (>= 2.2.6) in your Gemfile.')
        end
      end
    end
  end
end
