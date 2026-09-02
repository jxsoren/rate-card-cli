# frozen_string_literal: true

require 'parallel'

module RateCard
  # The fetch engine and the assembled result.
  #
  # One call per (weight, zone); each response is harvested for every selected
  # service, via the provider's #parse_rate_response. A cell whose call failed
  # is nil and is listed in #failures — never 0.0, which in a rate table reads
  # as a real free rate.
  class Grid
    THREADS = 8
    RETRY_BACKOFF = [0.5, 1.0].freeze

    # on_progress: called with no arguments after each completed call.
    # retry_sleeper: injected so retry backoff is testable without waiting.
    def self.build(spec:, client:, provider:, on_progress: nil, retry_sleeper: ->(seconds) { sleep(seconds) })
      new(spec, provider).tap { |grid| grid.send(:fetch_all, client, on_progress, retry_sleeper) }
    end

    attr_reader :spec

    # provider defaults to nil only for specs that construct a Grid directly to
    # seed @cells as a fixture and never fetch — #build (the real constructor)
    # always supplies one.
    def initialize(spec, provider = nil)
      @spec = spec
      @provider = provider
      @cells = {}
      @failures = []
      @warnings = Hash.new(0)
      @succeeded = 0
      @mutex = Mutex.new
    end

    def value(service_id:, rate_key:, weight:, zone:)
      @cells[[service_id, rate_key, weight, zone]]
    end

    def failures
      @failures.sort_by { |f| [f.weight, f.zone] }
    end

    def warnings
      @warnings.map { |(message, scope), count| Warning.new(message: message, count: count, scope: scope) }
               .sort_by { |warning| [scope_rank(warning), -warning.count, warning.message] }
    end

    def all_failed?
      @succeeded.zero? && @failures.any?
    end

    def any_rates?
      @cells.values.any?
    end

    private

    attr_reader :provider

    def fetch_all(client, on_progress, retry_sleeper)
      Parallel.each(cell_coordinates, in_threads: THREADS) do |weight, zone|
        fetch_cell(client, weight, zone, retry_sleeper)
        @mutex.synchronize { on_progress&.call }
      end
    end

    def cell_coordinates
      spec.rows.product(spec.zones)
    end

    def fetch_cell(client, weight, zone, retry_sleeper)
      payload = provider.build_payload(spec: spec, weight: weight, address: spec.address_for(zone))
      result = fetch_with_transient_retry(client, payload, retry_sleeper)
      record_response(result, weight, zone)
      @mutex.synchronize { @succeeded += 1 }
    rescue Unauthorized
      raise
    rescue StandardError => e
      @mutex.synchronize do
        @failures << Failure.new(weight: weight, zone: zone, message: e.message)
      end
    end

    def fetch_with_transient_retry(client, payload, retry_sleeper)
      attempt = 0
      loop do
        body = client.fetch_rates(payload)
        result = provider.parse_rate_response(body, spec: spec)
        return result unless result[:transient] && attempt < RETRY_BACKOFF.length

        retry_sleeper.call(RETRY_BACKOFF[attempt])
        attempt += 1
      end
    end

    def record_response(result, weight, zone)
      @mutex.synchronize do
        record_warnings(result)

        spec.services.each do |service|
          spec.rate_keys.each do |rate_key|
            raw = result[:service_values].dig(service.id, rate_key)
            @cells[[service.id, rate_key, weight, zone]] = coerce(raw)
          end
        end
      end
    end

    # Caller holds @mutex.
    def record_warnings(result)
      result[:warnings].each { |message| @warnings[[message, Warning::ACCOUNT]] += 1 }

      spec.services.each do |service|
        detail = result[:service_errors][service.id]
        next if detail.nil?

        @warnings[["#{service.name} (#{service.id}): #{detail}", Warning::SERVICE]] += 1
      end
    end

    def scope_rank(warning)
      warning.account_wide? ? 1 : 0
    end

    # nil stays nil. Anything numeric becomes a Float. Never defaults to zero.
    def coerce(raw)
      return nil if raw.nil? || raw.to_s.strip.empty?

      Float(raw)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
