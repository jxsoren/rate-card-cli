# frozen_string_literal: true

module RateCard
  module Providers
    module EHub
      # Implements the provider interface documented in
      # docs/superpowers/specs/2026-09-02-provider-abstraction-design.md by
      # delegating to the eHub-specific classes in this directory.
      class Provider
        LABEL = 'eHub'

        # eHub answers a disguised-success rate-limit hiccup as an HTTP 201 with a
        # per-service errors field describing it, so Client's status-code retry
        # never sees it. Left alone, the exact same request prices a different
        # random set of cells on every run.
        TRANSIENT_ERROR_PATTERN = /too many requests|please try again|slow down/i

        def label
          LABEL
        end

        def read_credential(ui:, io: $stdin)
          TokenPrompt.read(ui: ui, io: io)
        end

        def identify(credential)
          Token.decode(credential)
        end

        def client(credential)
          Client.new(token: credential)
        end

        def parse_services(body)
          ServiceCatalog.from_response(body)
        end

        def build_payload(spec:, weight:, address:)
          Shipment.new(spec: spec, weight: weight, address: address).payload
        end

        # Normalizes one /rates response into what Grid needs to record a cell:
        # - transient: a disguised-success rate-limit hiccup that should be retried
        # - warnings: the response-level warnings array (account-wide)
        # - service_errors: { service_id => message } for selected services only
        # - service_values: { service_id => { rate_key => raw_value_or_nil } }
        def parse_rate_response(body, spec:)
          by_id = index_by_service_id(body)
          {
            transient: transient?(spec, by_id),
            warnings: response_warnings(body),
            service_errors: service_errors(spec, by_id),
            service_values: service_values(spec, by_id)
          }
        end

        private

        def transient?(spec, by_id)
          spec.services.any? { |service| error_detail(by_id[service.id]) =~ TRANSIENT_ERROR_PATTERN }
        end

        def service_errors(spec, by_id)
          spec.services.each_with_object({}) do |service, acc|
            detail = error_detail(by_id[service.id])
            acc[service.id] = detail if detail
          end
        end

        def service_values(spec, by_id)
          spec.services.each_with_object({}) do |service, acc|
            entry = by_id[service.id]
            acc[service.id] = spec.rate_keys.each_with_object({}) do |rate_key, values|
              field = RunSpec::RATE_KEY_FIELDS.fetch(rate_key)
              values[rate_key] = entry && entry[field]
            end
          end
        end

        def response_warnings(body)
          return [] unless body.is_a?(Hash)

          Array(body['warnings']).map(&:to_s).reject { |message| message.strip.empty? }
        end

        # `errors` is documented as populated when a service could not be rated. It
        # comes back as a string, but an array is accepted so a list of carrier
        # messages reads as one line instead of raising.
        def error_detail(entry)
          raw = entry && entry['errors']
          detail = Array(raw).map(&:to_s).reject { |message| message.strip.empty? }.join('; ')
          detail.empty? ? nil : detail
        end

        def index_by_service_id(body)
          entries = body.is_a?(Hash) ? (body['service_rates'] || []) : []
          entries.each_with_object({}) do |entry, acc|
            id = entry['service_id']
            acc[id.to_i] = entry unless id.nil?
          end
        end
      end
    end
  end
end
