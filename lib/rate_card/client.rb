# frozen_string_literal: true

require 'faraday'
require 'json'

module RateCard
  # The single network seam. Talks to eHub production and classifies every
  # outcome into: a parsed Hash, Unauthorized, or RequestFailed. Callers never
  # see a Faraday exception.
  class Client
    BASE_URL = 'https://api.essentialhub.com'
    PATH = '/api/v2/rates/'

    # 429 and 5xx are transient; everything else is a decision, not a hiccup.
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
      attempt = 0
      loop do
        status, body = post(payload)
        return body if status == 201

        raise Unauthorized, 'production rejected the token (403)' if status == 403

        unless RETRYABLE.include?(status) && attempt < BACKOFF.length
          raise RequestFailed, "rate call failed with HTTP #{status}#{error_detail(body)}"
        end

        @sleeper.call(BACKOFF[attempt])
        attempt += 1
      end
    end

    private

    def post(payload)
      response = @connection.post(PATH, JSON.generate(payload))
      [response.status, parse(response.body)]
    rescue Faraday::Error => e
      raise RequestFailed, "rate call failed: #{e.message}"
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
