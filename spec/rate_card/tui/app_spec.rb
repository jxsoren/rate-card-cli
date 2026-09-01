# frozen_string_literal: true

require 'base64'
require 'pathname'
require 'tmpdir'
require 'support/keys'

# The wizard's coverage, carried over from wizard_spec after the Bubbletea
# switch. Nothing here runs a Bubbletea::Runner: App is a plain
# init/update/view model, so a run is just a list of key messages fed to
# #update — no pty, no fake prompt object, no blocking reads.
RSpec.describe RateCard::TUI::App do
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

  let(:catalog_client) { FakeClient.new(services: catalog_body) }

  def app(output_base: Pathname.new('/tmp/rc'), client: catalog_client, tok: token)
    described_class.new(token: tok, output_base: output_base,
                        client_factory: ->(_token) { client })
  end

  # Feeds keys through #update the way the runner would, and runs any Proc
  # command inline so the catalogue lookup resolves without a thread.
  def press(model, *messages)
    messages.flatten.each do |message|
      _model, command = model.update(message)
      run_command(model, command)
    end
    model
  end

  def run_command(model, command)
    return unless command.is_a?(Proc)

    result = command.call
    return unless result.is_a?(Bubbletea::Message)

    _model, next_command = model.update(result)
    run_command(model, next_command)
  end

  def start(**options)
    model = app(**options)
    _model, command = model.init
    run_command(model, command)
    model
  end

  # carrier (USPS is first), services (tick first), zones, unit, weights,
  # package type, rate keys — each defaulted or first-choice.
  def answer_happy_path(model)
    press(model, Keys.enter)                     # rate by: weight
    press(model, Keys.enter)                     # carrier: usps
    press(model, Keys.space, Keys.enter)         # services: first
    press(model, Keys.enter)                     # zones: default 1-8
    press(model, Keys.enter)                     # unit: oz
    press(model, Keys.enter)                     # weights: default 1-16
    press(model, Keys.enter)                     # package type
    press(model, Keys.enter)                     # rate keys: both pre-ticked
    model
  end

  def answer_rest(model)
    press(model, Keys.space, Keys.enter)         # services: first
    press(model, Keys.enter)                     # zones
    press(model, Keys.enter)                     # unit
    press(model, Keys.enter)                     # weights
    press(model, Keys.enter)                     # package type
    press(model, Keys.enter)                     # rate keys
    model
  end

  # The recap opens on Back, so starting the run is up-then-enter.
  def start_run(model)
    press(model, Keys.up, Keys.enter)
  end

  # Reaches :fetching without letting the fetch's Proc command run — used when a
  # test wants to inject its own ProgressAdvanced messages instead of letting a
  # FakeClient-backed fetch complete synchronously and race past :fetching.
  def enter_fetching_stage_without_fetching(model)
    press(model, Keys.up)
    model.update(Keys.enter)
  end

  # The confirm is reached but not answered, so the spec can be inspected
  # without the fetch starting.
  def spec_from(model)
    model.send(:build_spec)
  end

  describe 'the happy path' do
    it 'builds a validated RunSpec' do
      model = answer_happy_path(start)

      spec = spec_from(model)
      expect(spec).to be_a(RateCard::RunSpec)
      expect { spec.validate! }.not_to raise_error
    end

    it 'carries the token and decoded customer identity onto the spec' do
      spec = spec_from(answer_happy_path(start))

      expect(spec.token).to eq(token)
      expect(spec.customer_name).to eq('ops@acme.test')
      expect(spec.customer_id).to eq(1042)
    end

    it 'defaults zones to the carrier full range, oz, 1-16, parcel, both rate keys' do
      spec = spec_from(answer_happy_path(start))

      expect(spec.zones).to eq((1..8).to_a)
      expect(spec.weight_unit).to eq(:oz)
      expect(spec.weights).to eq((1..16).to_a)
      expect(spec.package_type).to eq('parcel')
      expect(spec.rate_keys).to eq(%i[shipper_rate meter_rate])
    end

    it 'sets output_base and started_at' do
      spec = spec_from(answer_happy_path(start))

      expect(spec.output_base).to eq(Pathname.new('/tmp/rc'))
      expect(spec.started_at).to be_a(Time)
    end

    it 'offers only the services discovered for the chosen carrier' do
      model = start
      press(model, Keys.enter) # rate by: weight
      press(model, Keys.enter) # carrier: usps

      expect(model.view).to include('USPS Ground Advantage')
      expect(model.view).not_to include('FedEx Ground')
    end
  end

  describe 'the transcript' do
    it 'confirms the decoded customer as soon as the catalogue loads' do
      model = start

      expect(model.view).to include('ops@acme.test', '1042')
    end

    it 'keeps each answer on screen as the wizard moves on' do
      model = answer_happy_path(start)

      expect(model.view).to include('services: USPS Ground Advantage')
      expect(model.view).to include('zones: 1-8')
      expect(model.view).to include('weights: 1-16')
    end
  end

  describe 'the recap' do
    it 'repeats every answer back before the confirm' do
      view = answer_happy_path(start).view

      expect(view).to include('USPS')
      expect(view).to include('USPS Ground Advantage')
      expect(view).to include('zones 1-8')
      expect(view).to include('weights 1-16 oz')
      expect(view).to include('parcel')
      expect(view).to include('shipper rate, meter rate')
      expect(view).to include('128 rate calls against production')
      expect(view).to include('Run this rate card?')
    end
  end

  describe 'the Run/Back choice' do
    it 'opens on Back, so a stray enter goes back instead of starting a run' do
      model = answer_happy_path(start)
      press(model, Keys.enter)

      expect(model.view).to include('Rate columns')
      expect(model.spec).to be_nil
    end
  end

  describe 'going back' do
    it 'reopens the previous question and drops its answer from the transcript' do
      model = answer_happy_path(start)
      press(model, Keys.esc) # confirm -> rate columns

      expect(model.view).to include('Rate columns')
      expect(model.view).not_to include('128 rate calls')
      expect(model.view).not_to include('columns: shipper rate')
    end

    it 'walks all the way back to the first question' do
      model = answer_happy_path(start)
      8.times { press(model, Keys.esc) }

      expect(model.view).to include('Rate by')
    end

    it 'stays put at the first question rather than falling out of the wizard' do
      model = start
      3.times { press(model, Keys.esc) }

      expect(model.view).to include('Rate by')
      expect(model).not_to be_cancelled
    end

    it 'reopens a select on the answer it already has' do
      model = start
      press(model, Keys.enter) # rate by: weight
      press(model, Keys.down, Keys.enter) # carrier: fedex
      press(model, Keys.esc)

      press(model, Keys.enter) # take whatever the cursor sits on
      expect(spec_from(answer_rest(model)).carrier).to eq('FedEx')
    end

    it 'keeps an amended answer and forgets the ones that followed it' do
      model = answer_happy_path(start)
      press(model, Keys.esc)                     # back to rate columns
      press(model, Keys.esc)                     # back to package type (or weights)
      press(model, Keys.esc)                     # back to weights
      press(model, Keys.type('1-4'), Keys.enter) # amend
      press(model, Keys.enter)                   # package type
      press(model, Keys.enter)                   # rate columns

      spec = spec_from(model)
      expect(spec.weights).to eq([1, 2, 3, 4])
      expect(model.view.scan('weights:').length).to eq(1)
    end

    # A carrier change invalidates the services picked under the old one, so
    # they are not carried forward as ticks into a list they are not in.
    it 'forgets the services when the carrier changes' do
      model = answer_happy_path(start)
      6.times { press(model, Keys.esc) } # back to services
      press(model, Keys.esc)             # back to carrier
      press(model, Keys.down, Keys.enter) # carrier: fedex

      expect(model.view).to include('FedEx Ground')
      expect(model.view).not_to include('USPS Ground Advantage')
    end
  end

  describe 'cancelling' do
    it 'still renders after ctrl-c' do
      model = answer_happy_path(start)
      press(model, Keys.ctrl_c)

      expect { model.view }.not_to raise_error
    end

    it 'is cancelled by ctrl-c at any point' do
      model = start
      press(model, Keys.ctrl_c)

      expect(model).to be_cancelled
    end
  end

  describe 'bad input' do
    it 're-prompts when the zone answer contains no valid zone' do
      model = start
      press(model, Keys.enter) # rate by: weight
      press(model, Keys.enter) # carrier
      press(model, Keys.space, Keys.enter) # services
      press(model, Keys.type('99'), Keys.enter)

      expect(model.view).to include('no valid zones')

      press(model, Keys.type('1-3'), Keys.enter)
      expect(model.view).to include('zones: 1-3')
    end

    it 're-prompts when the weight answer is unparseable' do
      model = start
      press(model, Keys.enter) # rate by: weight
      press(model, Keys.enter) # carrier
      press(model, Keys.space, Keys.enter) # services
      press(model, Keys.enter) # zones
      press(model, Keys.enter) # unit
      press(model, Keys.type('abc'), Keys.enter)

      expect(model.view).to include('range like 1-16')
    end
  end

  describe 'the catalogue lookup' do
    it 'reports NoServices when the catalogue is empty' do
      model = start(client: FakeClient.new(services: { 'services' => [] }))

      expect(model.error).to be_a(RateCard::NoServices)
    end

    # The DHL regression: the wizard offered a carrier it had no zone chart for,
    # and Addresses.for_carrier quietly answered with USPS addresses.
    it 'drops services whose carrier has no zone chart from the menu' do
      body = { 'services' => [
        { 'service_id' => 1172, 'service_code' => 'GroundAdvantage',
          'service' => 'USPS Ground Advantage', 'carrier_code' => 'usps' },
        { 'service_id' => 900, 'service_code' => 'DHL_BPM',
          'service' => 'DHL Ecommerce BPM Ground', 'carrier_code' => 'dhl_ecommerce' }
      ] }

      model = start(client: FakeClient.new(services: body))

      expect(model.error).to be_nil
      expect(model.view).not_to include('DHL')
    end

    it 'reports UnsupportedCarrier when every service is on a chartless carrier' do
      body = { 'services' => [
        { 'service_id' => 900, 'service_code' => 'DHL_BPM',
          'service' => 'DHL Ecommerce BPM Ground', 'carrier_code' => 'dhl_ecommerce' }
      ] }

      model = start(client: FakeClient.new(services: body))

      expect(model.error).to be_a(RateCard::UnsupportedCarrier)
      expect(model.error.message).to include('DHL')
    end

    it 'carries Unauthorized out of the loop rather than raising through it' do
      rejected = RateCard::Unauthorized.new('production rejected this token')

      model = nil
      expect { model = start(client: FakeClient.new(services: rejected)) }.not_to raise_error
      expect(model.error).to be_a(RateCard::Unauthorized)
    end
  end

  describe 'the fetch' do
    # Moved here from runner_spec when the fetch moved into the event loop.
    # Still before the first call, so a bad path is not discovered after 128.
    it 'checks writability before making any call, and reports rather than raising' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'blocker'), 'x')
        client = FakeClient.new(services: catalog_body) { |_w, _p| { 'service_rates' => [] } }
        model = start(output_base: Pathname.new(File.join(dir, 'blocker', 'sub')), client: client)
        answer_happy_path(model)

        expect { start_run(model) }.not_to raise_error
        expect(model.error).to be_a(RateCard::OutputNotWritable)
        expect(client.payloads).to be_empty
        expect(model.grid).to be_nil
      end
    end

    it 'carries the finished grid out of the loop for the caller to report on' do
      Dir.mktmpdir do |dir|
        client = FakeClient.new(services: catalog_body) do |weight, _postal|
          { 'service_rates' => [{ 'service_id' => 1172, 'rate' => weight * 1.0 }] }
        end
        model = start(output_base: Pathname.new(dir), client: client)
        answer_happy_path(model)
        start_run(model)

        expect(model.grid).to be_a(RateCard::Grid)
        expect(model.grid.any_rates?).to be(true)
        expect(model).not_to be_cancelled
      end
    end

    it 'records the failed count from every ProgressAdvanced message' do
      model = start
      answer_happy_path(model)

      model.update(RateCard::TUI::ProgressAdvanced.new(completed: 1, failed: 0))
      model.update(RateCard::TUI::ProgressAdvanced.new(completed: 2, failed: 1))
      model.update(RateCard::TUI::ProgressAdvanced.new(completed: 3, failed: 1))

      expect(model.instance_variable_get(:@failure_history)).to eq([0, 1, 1])
    end

    it 'omits the sparkline while every call has succeeded' do
      model = start
      answer_happy_path(model)
      enter_fetching_stage_without_fetching(model)

      model.update(RateCard::TUI::ProgressAdvanced.new(completed: 1, failed: 0))

      expect(model.view).not_to include('failed')
    end

    it 'shows a sparkline once a failure happens, and keeps it after later clean ticks' do
      model = start
      answer_happy_path(model)
      enter_fetching_stage_without_fetching(model)

      model.update(RateCard::TUI::ProgressAdvanced.new(completed: 1, failed: 0))
      model.update(RateCard::TUI::ProgressAdvanced.new(completed: 2, failed: 1))
      view_after_failure = model.view

      model.update(RateCard::TUI::ProgressAdvanced.new(completed: 3, failed: 1))
      view_after_clean_tick = model.view

      expect(view_after_failure).to include('1 failed')
      expect(view_after_clean_tick).to include('1 failed')
    end
  end

  describe 'package types' do
    def catalog_with(package_types)
      { 'services' => [{ 'service_id' => 1172, 'service_code' => 'GroundAdvantage',
                         'service' => 'USPS Ground Advantage', 'carrier_code' => 'usps',
                         'package_types' => package_types }] }
    end

    it 'offers the package types the selected service reports' do
      body = catalog_with([{ 'type' => 'parcel' }, { 'type' => 'flat_rate_box' }])
      model = start(client: FakeClient.new(services: body))
      press(model, Keys.enter)             # rate by: weight (single USPS service present)
      press(model, Keys.space, Keys.enter) # services (single carrier, so no carrier step)
      press(model, Keys.enter)             # zones
      press(model, Keys.enter)             # unit

      press(model, Keys.enter)             # weights -> package type field
      expect(model.view).to include('flat_rate_box')
    end

    it 'falls back to the built-in package types when the catalogue lists none' do
      model = start(client: FakeClient.new(services: catalog_with([])))
      press(model, Keys.enter)
      press(model, Keys.space, Keys.enter)
      press(model, Keys.enter)
      press(model, Keys.enter)
      press(model, Keys.enter)

      expect(model.view).to include('flat_rate_envelope')
    end
  end

  describe 'cubic mode' do
    def answer_cubic_path(model)
      press(model, Keys.down, Keys.enter)  # rate by: cubic dimensions
      press(model, Keys.space, Keys.enter) # services: first (USPS, only carrier left)
      press(model, Keys.enter)             # zones
      press(model, Keys.enter)             # cubic tiers: all pre-ticked
      press(model, Keys.enter)             # package type
      press(model, Keys.enter)             # rate keys
      model
    end

    it 'restricts the carrier to USPS and skips the weight-unit question' do
      model = answer_cubic_path(start)

      expect(model.view).not_to include('Weight unit')
      spec = spec_from(model)
      expect(spec.carrier).to eq('USPS')
    end

    it 'offers the ten official cubic tiers, all ticked by default' do
      model = start
      press(model, Keys.down, Keys.enter)  # rate by: cubic dimensions
      press(model, Keys.space, Keys.enter) # services
      press(model, Keys.enter)             # zones

      expect(model.view).to include('Tier 1')
      expect(model.view).to include('10/10 selected')
    end

    it 'builds a validated RunSpec in cubic mode with every tier selected' do
      spec = spec_from(answer_cubic_path(start))

      expect(spec.rate_mode).to eq(:cubic)
      expect(spec.cubic_tiers).to eq((1..10).to_a)
      expect { spec.validate! }.not_to raise_error
    end

    it 'skips the rate-by question entirely when the token has no USPS services' do
      body = { 'services' => [{ 'service_id' => 392, 'service_code' => 'FEDEX_GROUND',
                                'service' => 'FedEx Ground', 'carrier_code' => 'fedex' }] }
      model = start(client: FakeClient.new(services: body))

      expect(model.view).not_to include('Rate by')
      expect(model.view).to include('Services')
    end
  end
end
