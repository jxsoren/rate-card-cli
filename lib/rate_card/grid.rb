# frozen_string_literal: true

require 'parallel'

module RateCard
  # The fetch engine and the assembled result.
  #
  # One call per (weight, zone); each response is harvested for every selected
  # service, since eHub returns rates for all enabled services at once. A cell
  # whose call failed is nil and is listed in #failures — never 0.0, which in a
  # rate table reads as a real free rate.
  class Grid
    THREADS = 8

    # eHub answers these as an HTTP 201 "success" with the per-service errors
    # field describing a hiccup that clears on its own, so Client's status-code
    # retry never sees them. Left alone, the exact same request prices a
    # different random set of cells on every run.
    TRANSIENT_ERROR_PATTERN = /too many requests|please try again|slow down/i
    RETRY_BACKOFF = [0.5, 1.0].freeze

    # on_progress: called with no arguments after each completed call.
    # retry_sleeper: injected so retry backoff is testable without waiting.
    def self.build(spec:, client:, on_progress: nil, retry_sleeper: ->(seconds) { sleep(seconds) })
      new(spec).tap { |grid| grid.send(:fetch_all, client, on_progress, retry_sleeper) }
    end

    attr_reader :spec

    def initialize(spec)
      @spec = spec
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

    # What the API said went wrong on calls that otherwise succeeded: the
    # response-level `warnings` array and the per-service `errors` field. Both
    # arrive with an HTTP 201, so without this a carrier outage would show up as
    # a card of blank cells with nothing to explain them.
    #
    # This card's own services sort first, however loud the account-wide noise
    # is: one call rates every service on the token, so a token with 37 services
    # enabled can bury the two warnings that explain this card's blank cells
    # under thirty about services nobody selected.
    def warnings
      @warnings.map { |(message, scope), count| Warning.new(message: message, count: count, scope: scope) }
               .sort_by { |warning| [scope_rank(warning), -warning.count, warning.message] }
    end

    # True only when no call got through. Deliberately NOT "no cell has a
    # value": a run can have every call succeed and still price nothing, if the
    # API does not return the selected service (USPS First Class is not priced
    # above 13 oz, for instance). Conflating the two would blame the network for
    # what is really a service or weight selection problem.
    def all_failed?
      @succeeded.zero? && @failures.any?
    end

    # Did any cell actually get a rate? False means we have nothing to write.
    def any_rates?
      @cells.values.any?
    end

    private

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
      payload = Providers::EHub::Shipment.new(spec: spec, weight: weight, address: spec.address_for(zone)).payload
      body = fetch_with_transient_retry(client, payload, retry_sleeper)
      record_response(body, weight, zone)
      @mutex.synchronize { @succeeded += 1 }
    rescue Unauthorized
      # No later call can succeed; let it abort the whole run.
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
        return body unless transient_error?(body) && attempt < RETRY_BACKOFF.length

        retry_sleeper.call(RETRY_BACKOFF[attempt])
        attempt += 1
      end
    end

    # True when a selected service's errors field reads as a transient hiccup
    # rather than a real problem with this request.
    def transient_error?(body)
      by_id = index_by_service_id(body)
      spec.services.any? { |service| error_detail(by_id[service.id]) =~ TRANSIENT_ERROR_PATTERN }
    end

    def record_response(body, weight, zone)
      by_id = index_by_service_id(body)

      @mutex.synchronize do
        record_warnings(body, by_id)

        spec.services.each do |service|
          entry = by_id[service.id]
          spec.rate_keys.each do |rate_key|
            field = RunSpec::RATE_KEY_FIELDS.fetch(rate_key)
            @cells[[service.id, rate_key, weight, zone]] = coerce(entry && entry[field])
          end
        end
      end
    end

    # Caller holds @mutex.
    def record_warnings(body, by_id)
      response_warnings(body).each { |message| @warnings[[message, Warning::ACCOUNT]] += 1 }

      spec.services.each do |service|
        detail = error_detail(by_id[service.id])
        next if detail.nil?

        @warnings[["#{service.name} (#{service.id}): #{detail}", Warning::SERVICE]] += 1
      end
    end

    def scope_rank(warning)
      warning.account_wide? ? 1 : 0
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

    # nil stays nil. Anything numeric becomes a Float. Never defaults to zero.
    def coerce(raw)
      return nil if raw.nil? || raw.to_s.strip.empty?

      Float(raw)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
