# frozen_string_literal: true

require 'pathname'
require 'stringio'
require 'base64'

RSpec.describe RateCard::Providers::EHub::Provider do
  subject(:provider) { described_class.new }

  def jwt_for(customer_id, email)
    encode = ->(h) { Base64.urlsafe_encode64(JSON.generate(h), padding: false) }
    "#{encode.call({ alg: 'none' })}." \
      "#{encode.call({ data: { user: { customer_id: customer_id, email: email } } })}.sig"
  end

  def spec_with(services:, rate_keys: %i[shipper_rate meter_rate])
    RateCard::RunSpec.new(
      token: 'tok', customer_name: 'Acme', customer_id: 1, carrier: 'USPS',
      services: services, zones: [1], weight_unit: :oz, weights: [1],
      package_type: 'parcel', rate_keys: rate_keys,
      output_base: Pathname.new('/tmp'), show_table: true, started_at: Time.now
    )
  end

  let(:ground) do
    RateCard::Service.new(id: 1172, code: 'GroundAdvantage', name: 'GA', carrier: 'USPS')
  end

  it 'labels itself eHub' do
    expect(provider.label).to eq('eHub')
  end

  it 'reads a credential via the eHub token prompt' do
    token = jwt_for(1042, 'ops@acme.test')
    ui = RateCard::UI.new(io: StringIO.new)

    expect(provider.read_credential(ui: ui, io: StringIO.new("#{token}\n"))).to eq(token)
  end

  it 'identifies a credential by decoding it as an eHub JWT' do
    token = jwt_for(1042, 'ops@acme.test')

    expect(provider.identify(token)).to eq(name: 'ops@acme.test', customer_id: 1042, email: 'ops@acme.test')
  end

  it 'builds an eHub client for a credential' do
    expect(provider.client('secret-jwt')).to be_a(RateCard::Providers::EHub::Client)
  end

  it 'parses a services response into Service objects' do
    body = { 'services' => [{ 'service_id' => 1172, 'service_code' => 'GA', 'service' => 'GA',
                              'carrier_code' => 'usps' }] }

    services = provider.parse_services(body)

    expect(services.map(&:id)).to eq([1172])
  end

  it 'builds a rate request payload for one cell' do
    address = { address1: '1206 W 9440 S', city: 'South Jordan', state: 'UT',
                postal_code: '84094', country: 'US' }

    payload = provider.build_payload(spec: spec_with(services: [ground]), weight: 4, address: address)

    expect(payload[:shipment][:to_location]).to include(postal_code: '84094')
  end

  describe '#parse_rate_response' do
    it 'extracts the selected rate keys for each selected service' do
      body = { 'service_rates' => [{ 'service_id' => 1172, 'rate' => 5.0, 'meter_rate' => 6.0 }] }

      result = provider.parse_rate_response(body, spec: spec_with(services: [ground]))

      expect(result[:service_values][1172]).to eq(shipper_rate: 5.0, meter_rate: 6.0)
    end

    it 'omits a service missing from the response rather than raising' do
      result = provider.parse_rate_response({ 'service_rates' => [] }, spec: spec_with(services: [ground]))

      expect(result[:service_values][1172]).to eq(shipper_rate: nil, meter_rate: nil)
    end

    it 'collects the response-level warnings array' do
      body = { 'service_rates' => [], 'warnings' => ['carrier down'] }

      result = provider.parse_rate_response(body, spec: spec_with(services: [ground]))

      expect(result[:warnings]).to eq(['carrier down'])
    end

    it 'collects a selected service errors field, joining an array into one message' do
      body = { 'service_rates' => [{ 'service_id' => 1172, 'errors' => ['too heavy', 'bad zip'] }] }

      result = provider.parse_rate_response(body, spec: spec_with(services: [ground]))

      expect(result[:service_errors][1172]).to eq('too heavy; bad zip')
    end

    it 'omits a service with no errors field' do
      body = { 'service_rates' => [{ 'service_id' => 1172, 'rate' => 1.0 }] }

      result = provider.parse_rate_response(body, spec: spec_with(services: [ground]))

      expect(result[:service_errors]).to be_empty
    end

    it 'flags a disguised-success rate-limit hiccup on a selected service as transient' do
      body = { 'service_rates' => [{ 'service_id' => 1172, 'rate' => nil,
                                     'errors' => 'too many requests, please slow down' }] }

      result = provider.parse_rate_response(body, spec: spec_with(services: [ground]))

      expect(result[:transient]).to be(true)
    end

    it 'does not flag an unrelated error as transient' do
      body = { 'service_rates' => [{ 'service_id' => 1172, 'errors' => 'Weight exceeds maximum' }] }

      result = provider.parse_rate_response(body, spec: spec_with(services: [ground]))

      expect(result[:transient]).to be(false)
    end
  end
end
