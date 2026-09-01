# frozen_string_literal: true

require 'faraday'
require 'json'

module RateCard
  # The single network seam. Talks to eHub production and classifies every
  # outcome into: a parsed Hash, Unauthorized, or RequestFailed. Callers never
  # see a Faraday exception.
  #
  # The fetch engine depends on this split: it records a nil cell for each
  # RequestFailed and keeps going, but lets Unauthorized abort the whole run.
  # Narrowing Unauthorized to 403 only would turn a rejected token into a card
  # full of blank cells instead of one clear error — do not do that.
  class Client
    BASE_URL = 'https://api.ehub.com'
    # No trailing slash: that is the documented path, and a trailing slash would
    # rely on a redirect — which can drop the POST body.
    RATES_PATH = '/api/v2/rates'
    SERVICES_PATH = '/api/v2/services'
    # 'ecommerce' services are storefront integrations, not shippable rates.
    SERVICES_CATEGORY = 'shipping'

    # The rate endpoint answers 201; 200 is accepted too so a change on the
    # server side cannot turn a good response into a hard failure.
    SUCCESS = [200, 201].freeze
    # A rejected token will not improve on retry, so these are never retried.
    # Production answers 403, but 401 stays in the list: if it ever comes back
    # instead, we want one clear error rather than a card full of blank cells.
    UNAUTHORIZED = [401, 403].freeze
    # 429 and 5xx are transient; everything else is a decision, not a hiccup.
    # The gateway codes stay in: 502/503/504 are the load balancer, not the
    # rate engine, and they clear on their own within a backoff or two.
    RETRYABLE = [429, 500, 502, 503, 504].freeze
    BACKOFF = [0.5, 1.0].freeze

    # stubs: a Faraday::Adapter::Test::Stubs, for specs only.
    # sleeper: injected so retry backoff is testable without waiting.
    def initialize(token:, stubs: nil, sleeper: ->(seconds) { sleep(seconds) })
      @token = token
      @stubs = stubs
      @sleeper = sleeper
      @connection = build_connection
    end

    # Returns the parsed response body as a Hash.
    def fetch_rates(payload)
      request('rate call') { post(RATES_PATH, payload) }
    end

    # Returns the parsed body of the service catalogue for this token's customer.
    # Discovery uses this rather than a rate call: it costs nothing, and it lists
    # services that would not have quoted at the single probe weight and zone.
    def fetch_services
      request('service list call') { get(SERVICES_PATH, category: SERVICES_CATEGORY) }
    end

    private

    # Shared status handling: every call classifies into a Hash, Unauthorized,
    # or RequestFailed, and retries the transient statuses the same way.
    def request(label)
      attempt = 0
      loop do
        status, body = yield
        return body if SUCCESS.include?(status)

        if UNAUTHORIZED.include?(status)
          raise Unauthorized,
                "production rejected this token (HTTP #{status}). It may be expired, revoked, " \
                'or issued for a different environment — generate a new eHub API token and try again.'
        end

        unless RETRYABLE.include?(status) && attempt < BACKOFF.length
          raise RequestFailed, "#{label} failed with HTTP #{status}#{error_detail(body)}"
        end

        @sleeper.call(BACKOFF[attempt])
        attempt += 1
      end
    end

    def post(path, payload)
      response = @connection.post(path, JSON.generate(payload))
      [response.status, parse(response.body)]
    rescue Faraday::Error => e
      raise RequestFailed, "rate call failed: #{e.message}"
    end

    def get(path, params)
      response = @connection.get(path, params)
      [response.status, parse(response.body)]
    rescue Faraday::Error => e
      raise RequestFailed, "service list call failed: #{e.message}"
    end

    def parse(body)
      return body if body.is_a?(Hash)

      JSON.parse(body.to_s)
    rescue JSON::ParserError
      {}
    end

    def error_detail(body)
      message = body.is_a?(Hash) ? (body['error'] || body['message']) : nil
      message ? " (#{message})" : ''
    end

    def build_connection
      Faraday.new(url: BASE_URL) do |f|
        f.headers['Authorization'] = "Bearer #{@token}"
        f.headers['Content-Type'] = 'application/json'
        f.options.timeout = 30
        f.options.open_timeout = 10
        if @stubs
          f.adapter :test, @stubs
        else
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
