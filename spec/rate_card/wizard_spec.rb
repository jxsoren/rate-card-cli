# frozen_string_literal: true

require 'base64'
require 'pathname'
require 'stringio'
require 'tty-prompt'
require 'tty/prompt/test' # not autoloaded by tty-prompt; TTY::Prompt::Test needs it

RSpec.describe RateCard::Wizard do
  def jwt_for(customer_id, email)
    encode = ->(h) { Base64.urlsafe_encode64(JSON.generate(h), padding: false) }
    "#{encode.call({ alg: 'none' })}." \
      "#{encode.call({ data: { user: { customer_id: customer_id, email: email } } })}.sig"
  end

  let(:token) { jwt_for(1042, 'ops@acme.test') }

  let(:catalog_body) do
    { 'services' => [
      { 'service_id' => 1172, 'service_code' => 'GroundAdvantage',
        'service' => 'USPS Ground Advantage', 'carrier_code' => 'usps' },
      { 'service_id' => 392, 'service_code' => 'FEDEX_GROUND',
        'service' => 'FedEx Ground', 'carrier_code' => 'fedex' }
    ] }
  end

  let(:io) { StringIO.new }
  let(:ui) { RateCard::UI.new(io: StringIO.new) }
  let(:prompt) { TTY::Prompt::Test.new }
  let(:catalog_client) { FakeClient.new(services: catalog_body) }

  def wizard(output_base: Pathname.new('/tmp/rc'))
    described_class.new(
      prompt: prompt,
      ui: ui,
      output_base: output_base,
      client_factory: ->(_token) { catalog_client }
    )
  end

  # Drives the whole happy path: token, carrier USPS, first service, zones,
  # unit, weights, package type, rate keys, confirm.
  def answer_happy_path
    prompt.input << "#{token}\n"          # token (mask prompt)
    prompt.input << "\n"                  # carrier: first entry (USPS)
    prompt.input << " \n"                 # services: select first, submit
    prompt.input << "\n"                  # zones: accept default 1-8
    prompt.input << "\n"                  # weight unit: accept default oz
    prompt.input << "\n"                  # weight range: accept default 1-16
    prompt.input << "\n"                  # package type: accept default parcel
    prompt.input << "\n"                  # rate keys: accept default both
    prompt.input << "y\n"                 # confirm
    prompt.input.rewind
  end

  it 'returns a validated RunSpec on the happy path' do
    answer_happy_path

    spec = wizard.run

    expect(spec).to be_a(RateCard::RunSpec)
    expect { spec.validate! }.not_to raise_error
  end

  it 'carries the token and decoded customer identity onto the spec' do
    answer_happy_path

    spec = wizard.run

    expect(spec.token).to eq(token)
    expect(spec.customer_name).to eq('ops@acme.test')
    expect(spec.customer_id).to eq(1042)
  end

  it 'offers only services discovered from the probe call' do
    answer_happy_path

    spec = wizard.run

    expect(spec.services.map(&:id)).to eq([1172])
    expect(spec.carrier).to eq('USPS')
  end

  it 'defaults zones to the carrier full range, oz, 1-16, parcel, both rate keys' do
    answer_happy_path

    spec = wizard.run

    expect(spec.zones).to eq((1..8).to_a)
    expect(spec.weight_unit).to eq(:oz)
    expect(spec.weights).to eq((1..16).to_a)
    expect(spec.package_type).to eq('parcel')
    expect(spec.rate_keys).to eq(%i[shipper_rate meter_rate])
  end

  it 'sets output_base and started_at' do
    answer_happy_path

    spec = wizard.run

    expect(spec.output_base).to eq(Pathname.new('/tmp/rc'))
    expect(spec.started_at).to be_a(Time)
  end

  it 'returns nil when the user declines the confirmation' do
    prompt.input << "#{token}\n" << "\n" << " \n" << "\n" << "\n" << "\n" << "\n" << "\n"
    prompt.input << "n\n"
    prompt.input.rewind

    expect(wizard.run).to be_nil
  end

  it 'raises NoServices when the probe finds nothing' do
    empty_client = FakeClient.new(services: { 'services' => [] })
    prompt.input << "#{token}\n"
    prompt.input.rewind

    wiz = described_class.new(prompt: prompt, ui: ui, output_base: Pathname.new('/tmp'),
                             client_factory: ->(_t) { empty_client })

    expect { wiz.run }.to raise_error(RateCard::NoServices)
  end

  it 'lets Unauthorized from the probe propagate' do
    bad_client = FakeClient.new(services: RateCard::Unauthorized.new('rejected'))
    prompt.input << "#{token}\n"
    prompt.input.rewind

    wiz = described_class.new(prompt: prompt, ui: ui, output_base: Pathname.new('/tmp'),
                             client_factory: ->(_t) { bad_client })

    expect { wiz.run }.to raise_error(RateCard::Unauthorized)
  end

  # The three re-prompt loops. Each exists so one fat-fingered answer does not
  # cost the user the whole run, and none of them was covered by the plan's spec.
  it 're-prompts instead of raising when the pasted token is malformed' do
    prompt.input << "not-a-jwt\n"        # rejected, should re-prompt
    prompt.input << "#{token}\n"
    prompt.input << "\n" << " \n" << "\n" << "\n" << "\n" << "\n" << "\n"
    prompt.input << "y\n"
    prompt.input.rewind

    spec = wizard.run

    expect(spec.customer_id).to eq(1042)
  end

  it 're-prompts when the zone answer contains no valid zone' do
    prompt.input << "#{token}\n" << "\n" << " \n"
    prompt.input << "99\n"               # no such zone, should re-prompt
    prompt.input << "1-3\n"
    prompt.input << "\n" << "\n" << "\n" << "\n"
    prompt.input << "y\n"
    prompt.input.rewind

    expect(wizard.run.zones).to eq([1, 2, 3])
  end

  it 're-prompts when the weight answer is unparseable' do
    prompt.input << "#{token}\n" << "\n" << " \n" << "\n" << "\n"
    prompt.input << "abc\n"              # unparseable, should re-prompt
    prompt.input << "1-2\n"
    prompt.input << "\n" << "\n"
    prompt.input << "y\n"
    prompt.input.rewind

    expect(wizard.run.weights).to eq([1, 2])
  end

  describe '.parse_range' do
    it 'parses a dashed range' do
      expect(described_class.parse_range('1-8')).to eq((1..8).to_a)
    end

    it 'parses a comma list' do
      expect(described_class.parse_range('1,3,5')).to eq([1, 3, 5])
    end

    it 'parses a mix of ranges and singles, sorted and deduplicated' do
      expect(described_class.parse_range('5, 1-3, 2')).to eq([1, 2, 3, 5])
    end

    it 'tolerates whitespace' do
      expect(described_class.parse_range('  1 - 3 ')).to eq([1, 2, 3])
    end

    it 'returns an empty array for unparseable input' do
      expect(described_class.parse_range('abc')).to eq([])
    end

    it 'ignores a reversed range rather than looping forever' do
      expect(described_class.parse_range('8-1')).to eq([])
    end
  end
  # Valid package types are per-service (services[].package_types[].type), so a
  # contract-specific type like fedex_pak has to come from the catalogue, not a
  # hardcoded list.
  it 'offers the package types the selected service reports' do
    catalog_body['services'][0]['package_types'] = [{ 'type' => 'fedex_pak', 'name' => 'Pak' }]
    answer_happy_path

    spec = wizard.run

    expect(spec.package_type).to eq('fedex_pak')
  end

  it 'falls back to the built-in package types when the catalogue lists none' do
    answer_happy_path

    spec = wizard.run

    expect(spec.package_type).to eq(RateCard::Wizard::PACKAGE_TYPES.first)
  end
end
