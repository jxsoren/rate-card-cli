# frozen_string_literal: true

require 'faraday'

RSpec.describe RateCard::Providers::EHub::Client do
  # Builds a client whose HTTP layer replays the given [status, body] pairs.
  def client_replaying(*responses, sleeps: [])
    calls = responses.dup
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/api/v2/rates') do
        status, body = calls.shift
        [status, { 'Content-Type' => 'application/json' }, JSON.generate(body)]
      end
    end
    described_class.new(token: 'tok', stubs: stubs, sleeper: ->(s) { sleeps << s })
  end

  it 'returns the parsed body on success' do
    client = client_replaying([200, { 'service_rates' => [{ 'service_id' => 1 }] }])

    expect(client.fetch_rates({ shipment: {} })).to eq('service_rates' => [{ 'service_id' => 1 }])
  end

  it 'treats the 201 the rate endpoint actually returns as success' do
    client = client_replaying([201, { 'service_rates' => [{ 'service_id' => 1 }] }])

    expect(client.fetch_rates({ shipment: {} })).to eq('service_rates' => [{ 'service_id' => 1 }])
  end

  it 'raises Unauthorized on 401 without retrying' do
    sleeps = []
    client = client_replaying([401, { 'error' => 'bad token' }], sleeps: sleeps)

    expect { client.fetch_rates({}) }.to raise_error(RateCard::Unauthorized, /rejected/)
    expect(sleeps).to be_empty
  end

  it 'raises Unauthorized on 403 without retrying' do
    sleeps = []
    client = client_replaying([403, {}], sleeps: sleeps)

    expect { client.fetch_rates({}) }.to raise_error(RateCard::Unauthorized)
    expect(sleeps).to be_empty
  end

  it 'retries a 500 twice with backoff and succeeds on the third attempt' do
    sleeps = []
    client = client_replaying([500, {}], [500, {}], [200, { 'service_rates' => [] }], sleeps: sleeps)

    expect(client.fetch_rates({})).to eq('service_rates' => [])
    expect(sleeps).to eq([0.5, 1.0])
  end

  it 'raises RequestFailed after exhausting retries on 429' do
    client = client_replaying([429, {}], [429, {}], [429, {}])

    expect { client.fetch_rates({}) }.to raise_error(RateCard::RequestFailed, /429/)
  end

  it 'does not retry a 422 and reports the status' do
    sleeps = []
    client = client_replaying([422, { 'error' => 'bad zip' }], sleeps: sleeps)

    expect { client.fetch_rates({}) }.to raise_error(RateCard::RequestFailed, /422/)
    expect(sleeps).to be_empty
  end

  describe '#fetch_services' do
    it 'GETs the shipping catalogue and returns the parsed body' do
      captured = nil
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('/api/v2/services') do |env|
          captured = env
          [200, { 'Content-Type' => 'application/json' },
           JSON.generate('services' => [{ 'service_id' => 1172 }])]
        end
      end
      client = described_class.new(token: 'secret-jwt', stubs: stubs)

      expect(client.fetch_services).to eq('services' => [{ 'service_id' => 1172 }])
      expect(captured.params).to eq('category' => 'shipping')
      expect(captured.request_headers['Authorization']).to eq('Bearer secret-jwt')
    end

    it 'raises Unauthorized on 403 so discovery fails loudly rather than empty' do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('/api/v2/services') { [403, {}, '{}'] }
      end
      client = described_class.new(token: 'tok', stubs: stubs, sleeper: ->(_) {})

      expect { client.fetch_services }.to raise_error(RateCard::Unauthorized)
    end

    it 'reports the status when the service list call fails' do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('/api/v2/services') { [422, {}, '{}'] }
      end
      client = described_class.new(token: 'tok', stubs: stubs, sleeper: ->(_) {})

      expect { client.fetch_services }
        .to raise_error(RateCard::RequestFailed, /service list call failed with HTTP 422/)
    end
  end

  describe '#fetch_zone_addresses' do
    it 'GETs the per-service zone_addresses path and returns the parsed body' do
      captured = nil
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('/api/v2/services/9001/zone_addresses') do |env|
          captured = env
          [200, { 'Content-Type' => 'application/json' },
           JSON.generate('zones' => { '1' => { 'city' => 'Sandy' } })]
        end
      end
      client = described_class.new(token: 'secret-jwt', stubs: stubs)

      expect(client.fetch_zone_addresses(9001)).to eq('zones' => { '1' => { 'city' => 'Sandy' } })
      expect(captured.params).to eq({})
      expect(captured.request_headers['Authorization']).to eq('Bearer secret-jwt')
    end

    it 'passes from_postal_code through as a query param when given' do
      captured = nil
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('/api/v2/services/9001/zone_addresses') do |env|
          captured = env
          [200, { 'Content-Type' => 'application/json' }, JSON.generate('zones' => {})]
        end
      end
      client = described_class.new(token: 'tok', stubs: stubs)

      client.fetch_zone_addresses(9001, from_postal_code: '84070')

      expect(captured.params).to eq('from_postal_code' => '84070')
    end

    it 'omits from_postal_code from the query params when not given' do
      captured = nil
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('/api/v2/services/9001/zone_addresses') do |env|
          captured = env
          [200, { 'Content-Type' => 'application/json' }, JSON.generate('zones' => {})]
        end
      end
      client = described_class.new(token: 'tok', stubs: stubs)

      client.fetch_zone_addresses(9001)

      expect(captured.params).to eq({})
    end

    it 'raises Unauthorized on 403' do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('/api/v2/services/9001/zone_addresses') { [403, {}, '{}'] }
      end
      client = described_class.new(token: 'tok', stubs: stubs, sleeper: ->(_) {})

      expect { client.fetch_zone_addresses(9001) }.to raise_error(RateCard::Unauthorized)
    end

    it 'raises RequestFailed on a non-retryable failure' do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('/api/v2/services/9001/zone_addresses') { [422, {}, '{}'] }
      end
      client = described_class.new(token: 'tok', stubs: stubs, sleeper: ->(_) {})

      expect { client.fetch_zone_addresses(9001) }
        .to raise_error(RateCard::RequestFailed, /zone addresses call failed with HTTP 422/)
    end
  end

  it 'raises RequestFailed when the connection itself fails' do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/api/v2/rates') { raise Faraday::ConnectionFailed, 'boom' }
    end
    client = described_class.new(token: 'tok', stubs: stubs, sleeper: ->(_) {})

    expect { client.fetch_rates({}) }.to raise_error(RateCard::RequestFailed, /boom/)
  end

  it 'sends the bearer token and a json body' do
    captured = nil
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/api/v2/rates') do |env|
        captured = env
        [200, { 'Content-Type' => 'application/json' }, '{}']
      end
    end
    described_class.new(token: 'secret-jwt', stubs: stubs).fetch_rates({ shipment: { a: 1 } })

    expect(captured.request_headers['Authorization']).to eq('Bearer secret-jwt')
    # request_body, not body: Faraday's Env#body aliases to response_body once a
    # status is set, so reading .body after the call returns the response.
    expect(JSON.parse(captured.request_body)).to eq('shipment' => { 'a' => 1 })
  end
  # The documented endpoint is POST /api/v2/rates with no trailing slash. A
  # trailing slash relies on a redirect, and a redirected POST can lose its body.
  it 'posts to the documented path, without a trailing slash' do
    path = nil
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/api/v2/rates') do |env|
        path = env.url.path
        [201, { 'Content-Type' => 'application/json' }, '{}']
      end
    end
    described_class.new(token: 'tok', stubs: stubs).fetch_rates({ shipment: {} })

    expect(path).to eq('/api/v2/rates')
  end

  it 'uses the documented api.ehub.com host' do
    expect(described_class::BASE_URL).to eq('https://api.ehub.com')
  end
end
