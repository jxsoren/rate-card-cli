# frozen_string_literal: true

require 'base64'
require 'json'

RSpec.describe RateCard::Token do
  def jwt_for(payload)
    encode = ->(h) { Base64.urlsafe_encode64(JSON.generate(h), padding: false) }
    "#{encode.call({ alg: 'HS256' })}.#{encode.call(payload)}.signature"
  end

  describe '.decode' do
    it 'reads a real production payload, naming the account by its email' do
      token = jwt_for({ iat: 1_731_106_860,
                        data: { user: { id: 18_633, customer_id: 1_042,
                                        email: 'someone@example.com' },
                                scopes: ['api_public'] } })

      expect(described_class.decode(token))
        .to eq(name: 'someone@example.com', customer_id: 1_042, email: 'someone@example.com')
    end

    it 'names the account by email even when the token also carries a customer_name' do
      token = jwt_for({ data: { user: { customer_id: 1042, customer_name: 'Acme Fulfillment',
                                        email: 'ops@acme.test' } } })

      expect(described_class.decode(token))
        .to eq(name: 'ops@acme.test', customer_id: 1042, email: 'ops@acme.test')
    end

    it 'falls back to the customer id when there is no email' do
      token = jwt_for({ data: { user: { customer_id: 1042 } } })

      expect(described_class.decode(token))
        .to eq(name: 'customer 1042', customer_id: 1042, email: nil)
    end

    it 'treats a blank email as absent rather than naming the account empty' do
      token = jwt_for({ data: { user: { customer_id: 1042, email: '   ' } } })

      expect(described_class.decode(token))
        .to eq(name: 'customer 1042', customer_id: 1042, email: nil)
    end

    # Real JWT segments are unpadded base64url. These two cover both non-zero
    # padding residues (2 missing '=' chars, then 1), so the decoder keeps
    # working on unpadded input no matter the payload length.
    it 'decodes an unpadded payload two characters short of a base64 block' do
      token = jwt_for({ data: { user: { customer_id: 7, email: 'ab@b.test' } } })

      expect(described_class.decode(token)).to eq(name: 'ab@b.test', customer_id: 7,
                                                  email: 'ab@b.test')
    end

    it 'decodes an unpadded payload one character short of a base64 block' do
      token = jwt_for({ data: { user: { customer_id: 7, email: 'abc@b.test' } } })

      expect(described_class.decode(token)).to eq(name: 'abc@b.test', customer_id: 7,
                                                  email: 'abc@b.test')
    end

    it 'raises DecodeError, not TypeError, when the payload is a JSON array' do
      token = "header.#{Base64.urlsafe_encode64(JSON.generate([1, 2, 3]), padding: false)}.sig"

      expect { described_class.decode(token) }
        .to raise_error(RateCard::Token::DecodeError, /not a JSON object/)
    end

    it 'raises DecodeError when the payload is a bare JSON scalar' do
      token = "header.#{Base64.urlsafe_encode64('7', padding: false)}.sig"

      expect { described_class.decode(token) }
        .to raise_error(RateCard::Token::DecodeError, /not a JSON object/)
    end

    it 'decodes a Hash with no data.user nesting rather than raising' do
      token = "header.#{Base64.urlsafe_encode64(JSON.generate({ foo: 'bar' }), padding: false)}.sig"

      expect(described_class.decode(token))
        .to eq(name: 'unknown customer', customer_id: nil, email: nil)
    end

    it 'raises when the token does not have three segments' do
      expect { described_class.decode('not.ajwt') }
        .to raise_error(RateCard::Token::DecodeError, /three segments/)
    end

    it 'raises when the payload segment is not valid base64 json' do
      expect { described_class.decode('header.@@@@.signature') }
        .to raise_error(RateCard::Token::DecodeError, /does not look like an eHub API token/)
    end

    it 'still decodes when the payload has no customer_id, naming the account by email' do
      token = jwt_for({ data: { user: { email: 'ops@acme.test' } } })

      expect(described_class.decode(token))
        .to eq(name: 'ops@acme.test', customer_id: nil, email: 'ops@acme.test')
    end

    it 'raises on a nil or empty token' do
      expect { described_class.decode('') }.to raise_error(RateCard::Token::DecodeError)
      expect { described_class.decode(nil) }.to raise_error(RateCard::Token::DecodeError)
    end
  end
end
