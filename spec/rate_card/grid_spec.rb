# frozen_string_literal: true

require 'pathname'

RSpec.describe RateCard::Grid do
  let(:ground) do
    RateCard::Service.new(id: 1172, code: 'GroundAdvantage', name: 'GA', carrier: 'USPS')
  end
  let(:priority) do
    RateCard::Service.new(id: 684, code: 'Priority', name: 'Priority', carrier: 'USPS')
  end

  def spec_with(services:, zones: [1, 2], weights: [1, 2], rate_keys: %i[shipper_rate meter_rate])
    RateCard::RunSpec.new(
      token: 'tok', customer_name: 'Acme', customer_id: 1, carrier: 'USPS',
      services: services, zones: zones, weight_unit: :oz, weights: weights,
      package_type: 'parcel', rate_keys: rate_keys,
      output_base: Pathname.new('/tmp'), show_table: true, started_at: Time.now
    )
  end

  # Every call returns both services, priced off the weight for easy assertions.
  def both_services_responder
    lambda do |weight, _postal|
      { 'service_rates' => [
        { 'service_id' => 1172, 'rate' => weight * 1.0, 'meter_rate' => weight * 2.0 },
        { 'service_id' => 684, 'rate' => weight * 10.0, 'meter_rate' => weight * 20.0 }
      ] }
    end
  end

  it 'makes one call per weight and zone, not per service' do
    client = FakeClient.new(&both_services_responder)

    described_class.build(spec: spec_with(services: [ground, priority]), client: client)

    expect(client.payloads.length).to eq(4)
  end

  it 'populates every selected service from a single response' do
    grid = described_class.build(spec: spec_with(services: [ground, priority]),
                                 client: FakeClient.new(&both_services_responder))

    expect(grid.value(service_id: 1172, rate_key: :shipper_rate, weight: 2, zone: 1)).to eq(2.0)
    expect(grid.value(service_id: 684, rate_key: :shipper_rate, weight: 2, zone: 1)).to eq(20.0)
  end

  it 'reads the shipper rate from rate and the meter rate from meter_rate' do
    grid = described_class.build(spec: spec_with(services: [ground]),
                                 client: FakeClient.new(&both_services_responder))

    expect(grid.value(service_id: 1172, rate_key: :shipper_rate, weight: 1, zone: 1)).to eq(1.0)
    expect(grid.value(service_id: 1172, rate_key: :meter_rate, weight: 1, zone: 1)).to eq(2.0)
  end

  it 'records nil, not zero, for a cell whose call failed' do
    client = FakeClient.new do |weight, _postal|
      weight == 2 ? RateCard::RequestFailed.new('HTTP 500') : both_services_responder.call(weight, nil)
    end

    grid = described_class.build(spec: spec_with(services: [ground]), client: client)

    expect(grid.value(service_id: 1172, rate_key: :shipper_rate, weight: 2, zone: 1)).to be_nil
    expect(grid.value(service_id: 1172, rate_key: :shipper_rate, weight: 1, zone: 1)).to eq(1.0)
  end

  it 'records one failure per failed call, keyed by weight and zone' do
    client = FakeClient.new do |weight, _postal|
      weight == 2 ? RateCard::RequestFailed.new('HTTP 500') : both_services_responder.call(weight, nil)
    end

    grid = described_class.build(spec: spec_with(services: [ground, priority]), client: client)

    expect(grid.failures.length).to eq(2)
    expect(grid.failures.map { |f| [f.weight, f.zone] }).to contain_exactly([2, 1], [2, 2])
    expect(grid.failures.first.message).to include('HTTP 500')
  end

  it 'completes the run rather than aborting when some calls fail' do
    client = FakeClient.new do |weight, _postal|
      weight == 1 ? RateCard::RequestFailed.new('boom') : both_services_responder.call(weight, nil)
    end

    grid = described_class.build(spec: spec_with(services: [ground]), client: client)

    expect(grid.value(service_id: 1172, rate_key: :shipper_rate, weight: 2, zone: 2)).to eq(2.0)
  end

  it 'records nil when the response omits the selected service' do
    client = FakeClient.new { |_w, _p| { 'service_rates' => [{ 'service_id' => 684, 'rate' => 1.0 }] } }

    grid = described_class.build(spec: spec_with(services: [ground]), client: client)

    expect(grid.value(service_id: 1172, rate_key: :shipper_rate, weight: 1, zone: 1)).to be_nil
    expect(grid.failures).to be_empty
  end

  it 'records nil when the response has the service but a null rate field' do
    client = FakeClient.new do |_w, _p|
      { 'service_rates' => [{ 'service_id' => 1172, 'rate' => 1.5, 'meter_rate' => nil }] }
    end

    grid = described_class.build(spec: spec_with(services: [ground]), client: client)

    expect(grid.value(service_id: 1172, rate_key: :meter_rate, weight: 1, zone: 1)).to be_nil
  end

  it 'coerces a string rate to a float' do
    client = FakeClient.new { |_w, _p| { 'service_rates' => [{ 'service_id' => 1172, 'rate' => '5.85' }] } }

    grid = described_class.build(spec: spec_with(services: [ground]), client: client)

    expect(grid.value(service_id: 1172, rate_key: :shipper_rate, weight: 1, zone: 1)).to eq(5.85)
  end

  it 'reports all_failed? when every call failed' do
    client = FakeClient.new { |_w, _p| RateCard::RequestFailed.new('down') }

    grid = described_class.build(spec: spec_with(services: [ground]), client: client)

    expect(grid).to be_all_failed
    expect(grid).not_to be_any_rates
  end

  it 'is not all_failed? when at least one call succeeded' do
    grid = described_class.build(spec: spec_with(services: [ground]),
                                 client: FakeClient.new(&both_services_responder))

    expect(grid).not_to be_all_failed
    expect(grid).to be_any_rates
  end

  # The distinction that matters: calls all succeeded, but the API priced
  # nothing for the selected service. Blaming the network here would send the
  # user off debugging entirely the wrong thing.
  it 'is not all_failed? when calls succeeded but priced nothing' do
    client = FakeClient.new { |_w, _p| { 'service_rates' => [] } }

    grid = described_class.build(spec: spec_with(services: [ground]), client: client)

    expect(grid).not_to be_all_failed
    expect(grid).not_to be_any_rates
    expect(grid.failures).to be_empty
  end

  it 'reports any_rates? when only some cells were priced' do
    client = FakeClient.new do |weight, _postal|
      if weight == 1
        { 'service_rates' => [{ 'service_id' => 1172, 'rate' => 5.0 }] }
      else
        { 'service_rates' => [] }
      end
    end

    grid = described_class.build(spec: spec_with(services: [ground]), client: client)

    expect(grid).to be_any_rates
  end

  it 'propagates Unauthorized immediately instead of filling the grid with nils' do
    client = FakeClient.new { |_w, _p| RateCard::Unauthorized.new('rejected') }

    expect { described_class.build(spec: spec_with(services: [ground]), client: client) }
      .to raise_error(RateCard::Unauthorized)
  end

  it 'invokes the progress callback once per completed call' do
    ticks = 0
    described_class.build(spec: spec_with(services: [ground]),
                          client: FakeClient.new(&both_services_responder),
                          on_progress: -> { ticks += 1 })

    expect(ticks).to eq(4)
  end

  it 'sorts failures by weight then zone for a readable report' do
    client = FakeClient.new { |_w, _p| RateCard::RequestFailed.new('down') }

    grid = described_class.build(spec: spec_with(services: [ground], weights: [2, 1], zones: [2, 1]),
                                 client: client)

    expect(grid.failures.map { |f| [f.weight, f.zone] }).to eq([[1, 1], [1, 2], [2, 1], [2, 2]])
  end
end
