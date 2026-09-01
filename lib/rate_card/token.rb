# frozen_string_literal: true

require 'base64'
require 'json'

module RateCard
  # Reads claims out of an eHub JWT so we can show the user which customer a
  # pasted token belongs to. We decode so the user can confirm the account before
  # the tool spends money on billable production calls. Deliberately does NOT
  # verify the signature: these claims are displayed, never trusted for
  # authorization. The API's 401 is the only real check.
  module Token
    class DecodeError < Error; end

    module_function

    # Returns { name: String, customer_id: Integer, email: String|nil }.
    #
    # Real eHub tokens carry no customer_name, so the display name is normally
    # the account email — it tells the user which account they are about to bill
    # far better than a bare numeric id. The placeholder is a last resort.
    def decode(raw)
      payload = payload_from(raw)
      user = payload.dig('data', 'user') || {}

      customer_id = user['customer_id']
      raise DecodeError, 'token payload has no customer_id' unless customer_id.is_a?(Integer)

      email = presence(user['email'])
      name = presence(user['customer_name']) || email || "customer #{customer_id}"

      { name: name, customer_id: customer_id, email: email }
    end

    # nil for anything blank, so a whitespace-only claim never becomes a name.
    def presence(value)
      string = value.to_s.strip
      string.empty? ? nil : string
    end

    def payload_from(raw)
      segments = raw.to_s.split('.')
      raise DecodeError, 'token is not a JWT (expected three segments)' unless segments.length == 3

      encoded = segments[1]
      padded = encoded + ('=' * (-encoded.length % 4))
      parsed = JSON.parse(Base64.urlsafe_decode64(padded))
      raise DecodeError, 'token payload is not a JSON object' unless parsed.is_a?(Hash)

      parsed
    rescue ArgumentError, JSON::ParserError => e
      raise DecodeError, "token payload could not be decoded: #{e.message}"
    end
  end
end
