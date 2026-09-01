# frozen_string_literal: true

require 'base64'
require 'json'

module RateCard
  # Reads claims out of an eHub JWT so we can show the user which customer a
  # pasted token belongs to. We decode so the user can confirm they are pointed at
  # the intended production account before a run starts. Deliberately does NOT
  # verify the signature: these claims are displayed, never trusted for
  # authorization. The API's 401 is the only real check.
  module Token
    class DecodeError < Error; end

    module_function

    def decode(raw)
      payload = payload_from(raw)
      user = payload.dig('data', 'user') || {}

      customer_id = user['customer_id'] if user['customer_id'].is_a?(Integer)
      email = presence(user['email'])
      # FIXME - I don't even think we need a name field here tbh
      name = email || (customer_id ? "customer #{customer_id}" : 'unknown customer')

      { name: name, customer_id: customer_id, email: email }
    end

    def presence(value)
      string = value.to_s.strip
      string.empty? ? nil : string
    end

    def payload_from(raw)
      segments = raw.to_s.split('.')
      raise DecodeError, 'token is not a JWT (expected three segments)' unless segments.length == 3

      # urlsafe_decode64 restores missing '=' padding itself, which matters
      # because real JWT segments are always unpadded.
      parsed = JSON.parse(Base64.urlsafe_decode64(segments[1]))
      raise DecodeError, 'token payload is not a JSON object' unless parsed.is_a?(Hash)

      parsed
    rescue ArgumentError, JSON::ParserError
      raise DecodeError, 'this does not look like an eHub API token — please try again'
    end
  end
end
