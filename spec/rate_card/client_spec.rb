# frozen_string_literal: true

require 'faraday'

RSpec.describe RateCard::Client do
  # Builds a client whose HTTP layer replays the given [status, body] pairs.
  def client_replaying(*responses, sleeps: [])
    calls = responses.dup
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/api/v2/rates/') do
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

  it 'raises RequestFailed when the connection itself fails' do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/api/v2/rates/') { raise Faraday::ConnectionFailed, 'boom' }
    end
    client = described_class.new(token: 'tok', stubs: stubs, sleeper: ->(_) {})

    expect { client.fetch_rates({}) }.to raise_error(RateCard::RequestFailed, /boom/)
  end

  it 'sends the bearer token and a json body' do
    captured = nil
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/api/v2/rates/') do |env|
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
end
