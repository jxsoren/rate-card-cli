# frozen_string_literal: true

require 'base64'
require 'json'

RSpec.describe RateCard::Token do
  def jwt_for(payload)
    encode = ->(h) { Base64.urlsafe_encode64(JSON.generate(h), padding: false) }
    "#{encode.call({ alg: 'HS256' })}.#{encode.call(payload)}.signature"
  end

  describe '.decode' do
    it 'returns the customer name and id from the nested payload' do
      token = jwt_for({ data: { user: { customer_id: 1042, customer_name: 'Acme Fulfillment' } } })

      expect(described_class.decode(token)).to eq(name: 'Acme Fulfillment', customer_id: 1042)
    end

    it 'falls back to a placeholder name when the payload has no customer_name' do
      token = jwt_for({ data: { user: { customer_id: 1042 } } })

      expect(described_class.decode(token)).to eq(name: 'customer 1042', customer_id: 1042)
    end

    it 'decodes a payload whose base64 needs padding restored' do
      # A payload sized so its base64 length is not a multiple of 4.
      token = jwt_for({ data: { user: { customer_id: 7, customer_name: 'A' } } })

      expect(described_class.decode(token)[:customer_id]).to eq(7)
    end

    it 'raises when the token does not have three segments' do
      expect { described_class.decode('not.ajwt') }
        .to raise_error(RateCard::Token::DecodeError, /three segments/)
    end

    it 'raises when the payload segment is not valid base64 json' do
      expect { described_class.decode('header.@@@@.signature') }
        .to raise_error(RateCard::Token::DecodeError, /could not be decoded/)
    end

    it 'raises when the payload has no customer_id' do
      token = jwt_for({ data: { user: {} } })

      expect { described_class.decode(token) }
        .to raise_error(RateCard::Token::DecodeError, /no customer_id/)
    end

    it 'raises on a nil or empty token' do
      expect { described_class.decode('') }.to raise_error(RateCard::Token::DecodeError)
      expect { described_class.decode(nil) }.to raise_error(RateCard::Token::DecodeError)
    end
  end
end
