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

  it 'sweeps cubic tiers instead of weights when the spec is in cubic mode' do
    spec = RateCard::RunSpec.new(
      token: 'tok', customer_name: 'Acme', customer_id: 1, carrier: 'USPS',
      services: [ground], zones: [1], weight_unit: :oz, weights: [],
      rate_mode: :cubic, cubic_tiers: [8, 9],
      package_type: 'parcel', rate_keys: [:shipper_rate],
      output_base: Pathname.new('/tmp'), show_table: true, started_at: Time.now
    )
    client = FakeClient.new(&both_services_responder)

    grid = described_class.build(spec: spec, client: client)

    # Tier 8 caps at 128oz, tier 9 at 240oz — both_services_responder prices
    # off the wire weight, so distinct tiers must produce distinct rates.
    expect(grid.value(service_id: 1172, rate_key: :shipper_rate, weight: 8, zone: 1)).to eq(128.0)
    expect(grid.value(service_id: 1172, rate_key: :shipper_rate, weight: 9, zone: 1)).to eq(240.0)
  end

  it 'sorts failures by weight then zone for a readable report' do
    client = FakeClient.new { |_w, _p| RateCard::RequestFailed.new('down') }

    grid = described_class.build(spec: spec_with(services: [ground], weights: [2, 1], zones: [2, 1]),
                                 client: client)

    expect(grid.failures.map { |f| [f.weight, f.zone] }).to eq([[1, 1], [1, 2], [2, 1], [2, 2]])
  end
  # eHub answers these with an HTTP 201, so Client's status-code retry never
  # sees them. Left alone, they show up as a cell that is nil on one run and
  # priced on the next, for the exact same request.
  it 'retries a call whose selected service reports a transient error, and keeps the retried value' do
    attempts = Hash.new(0)
    mutex = Mutex.new
    client = FakeClient.new do |weight, _postal|
      count = mutex.synchronize { attempts[weight] += 1 }
      if count == 1
        { 'service_rates' => [{ 'service_id' => 1172, 'rate' => nil,
                                 'errors' => 'USPS received too many requests in test mode, please slow down and try again later' }] }
      else
        { 'service_rates' => [{ 'service_id' => 1172, 'rate' => weight * 1.0 }] }
      end
    end

    grid = described_class.build(spec: spec_with(services: [ground], zones: [1], weights: [1]),
                                 client: client, retry_sleeper: ->(_) {})

    expect(grid.value(service_id: 1172, rate_key: :shipper_rate, weight: 1, zone: 1)).to eq(1.0)
  end

  describe 'warnings' do
    # The docs are explicit that a carrier failure comes back as a 201 with a
    # populated warnings array, so a run can succeed and price nothing.
    it 'collects the response warnings array' do
      client = FakeClient.new do |_weight, _postal|
        { 'service_rates' => [], 'warnings' => ['FedEx returned error: Destination postal code missing or invalid'] }
      end

      grid = described_class.build(spec: spec_with(services: [ground], zones: [1], weights: [1]),
                                   client: client)

      expect(grid.warnings.map(&:message))
        .to eq(['FedEx returned error: Destination postal code missing or invalid'])
    end

    it 'counts a warning repeated across calls once, with its occurrence count' do
      client = FakeClient.new { |_w, _p| { 'service_rates' => [], 'warnings' => ['carrier down'] } }

      grid = described_class.build(spec: spec_with(services: [ground]), client: client)

      expect(grid.warnings.map { |w| [w.message, w.count] }).to eq([['carrier down', 4]])
    end

    it 'reports the per-service errors field, so a blank cell is explained' do
      client = FakeClient.new do |_weight, _postal|
        { 'service_rates' => [
          { 'service_id' => 1172, 'rate' => nil, 'errors' => 'Weight exceeds maximum' }
        ] }
      end

      grid = described_class.build(spec: spec_with(services: [ground], zones: [1], weights: [1]),
                                   client: client)

      expect(grid.warnings.map(&:message)).to eq(['GA (1172): Weight exceeds maximum'])
    end

    it 'ignores the errors field of a service that was not selected' do
      client = FakeClient.new do |_weight, _postal|
        { 'service_rates' => [{ 'service_id' => 684, 'errors' => 'not selected' }] }
      end

      grid = described_class.build(spec: spec_with(services: [ground], zones: [1], weights: [1]),
                                   client: client)

      expect(grid.warnings).to be_empty
    end

    it 'joins an errors array into one message' do
      client = FakeClient.new do |_weight, _postal|
        { 'service_rates' => [{ 'service_id' => 1172, 'errors' => ['too heavy', 'bad zip'] }] }
      end

      grid = described_class.build(spec: spec_with(services: [ground], zones: [1], weights: [1]),
                                   client: client)

      expect(grid.warnings.map(&:message)).to eq(['GA (1172): too heavy; bad zip'])
    end

    # The response-level array covers every service enabled on the token, not
    # just the selected ones, so it cannot be attributed to this card.
    it 'scopes the response warnings array to the whole token' do
      client = FakeClient.new { |_w, _p| { 'service_rates' => [], 'warnings' => ['carrier down'] } }

      grid = described_class.build(spec: spec_with(services: [ground], zones: [1], weights: [1]),
                                   client: client)

      expect(grid.warnings.map(&:scope)).to eq([:account])
    end

    it 'scopes a selected service errors field to this card' do
      client = FakeClient.new do |_weight, _postal|
        { 'service_rates' => [{ 'service_id' => 1172, 'errors' => 'Weight exceeds maximum' }] }
      end

      grid = described_class.build(spec: spec_with(services: [ground], zones: [1], weights: [1]),
                                   client: client)

      expect(grid.warnings.map(&:scope)).to eq([:service])
    end

    # This card's own services first, however loud the account-wide noise is.
    it 'orders this card\'s warnings ahead of the account-wide ones' do
      client = FakeClient.new do |_weight, _postal|
        { 'service_rates' => [{ 'service_id' => 1172, 'errors' => 'too heavy' }],
          'warnings' => ['Unauthorized Or Invalid pickup'] }
      end

      grid = described_class.build(spec: spec_with(services: [ground], zones: [1, 2], weights: [1]),
                                   client: client)

      expect(grid.warnings.map { |w| [w.scope, w.count] })
        .to eq([[:service, 2], [:account, 2]])
    end

    it 'has no warnings when every service rated cleanly' do
      grid = described_class.build(spec: spec_with(services: [ground]),
                                   client: FakeClient.new(&both_services_responder))

      expect(grid.warnings).to be_empty
    end
  end
end
