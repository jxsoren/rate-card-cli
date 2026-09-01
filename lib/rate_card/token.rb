# frozen_string_literal: true

require 'base64'
require 'json'

module RateCard
  # Reads claims out of an eHub JWT so we can show the user which customer a
  # pasted token belongs to. Deliberately does NOT verify the signature: these
  # claims are displayed, never trusted for authorization. The API's 401 is the
  # only real check.
  module Token
    class DecodeError < Error; end

    module_function

    # Returns { name: String, customer_id: Integer }.
    def decode(raw)
      payload = payload_from(raw)
      customer_id = payload.dig('data', 'user', 'customer_id')
      raise DecodeError, 'token payload has no customer_id' unless customer_id.is_a?(Integer)

      name = payload.dig('data', 'user', 'customer_name')
      name = "customer #{customer_id}" if name.nil? || name.to_s.strip.empty?

      { name: name.to_s, customer_id: customer_id }
    end

    def payload_from(raw)
      segments = raw.to_s.split('.')
      raise DecodeError, 'token is not a JWT (expected three segments)' unless segments.length == 3

      encoded = segments[1]
      padded = encoded + ('=' * (-encoded.length % 4))
      JSON.parse(Base64.urlsafe_decode64(padded))
    rescue ArgumentError, JSON::ParserError => e
      raise DecodeError, "token payload could not be decoded: #{e.message}"
    end
  end
end
