# frozen_string_literal: true

require 'pathname'
require 'stringio'
require 'tmpdir'

RSpec.describe RateCard::Runner do
  let(:ground) do
    RateCard::Service.new(id: 1172, code: 'GroundAdvantage', name: 'GA', carrier: 'USPS')
  end
  let(:io) { StringIO.new }
  let(:ui) { RateCard::UI.new(io: io) }

  def spec_in(dir, show_table: true)
    RateCard::RunSpec.new(
      token: 'tok', customer_name: 'Acme', customer_id: 1042, carrier: 'USPS',
      services: [ground], zones: [1, 2], weight_unit: :oz, weights: [1, 2],
      package_type: 'parcel', rate_keys: [:shipper_rate],
      output_base: Pathname.new(dir), show_table: show_table,
      started_at: Time.utc(2026, 8, 31, 15, 4, 22)
    )
  end

  def good_client
    FakeClient.new do |weight, _postal|
      { 'service_rates' => [{ 'service_id' => 1172, 'rate' => weight * 1.0 }] }
    end
  end

  around do |example|
    Dir.mktmpdir { |dir| @dir = dir; example.run }
  end

  # Runner no longer fetches — TUI::App does, inside the event loop, so the bar
  # can be live — so a spec builds the grid itself and hands over the result.
  def report(spec, client)
    grid = RateCard::Grid.build(spec: spec, client: client, provider: RateCard::Providers::EHub::Provider.new)
    described_class.new(spec: spec, grid: grid, ui: ui)
  end

  it 'returns exit code 0 on a fully successful run' do
    spec = spec_in(@dir)

    expect(report(spec, good_client).run).to eq(0)
  end

  it 'writes the csv files' do
    spec = spec_in(@dir)
    report(spec, good_client).run

    expect(spec.run_dir.join('GroundAdvantage_shipper_rate.csv')).to exist
  end

  it 'prints the table to stdout' do
    report(spec_in(@dir), good_client).run

    expect(io.string).to include('shipper rate')
    expect(io.string).to include('╭')
  end

  it 'skips the table when show_table is false but still writes files' do
    spec = spec_in(@dir, show_table: false)
    report(spec, good_client).run

    expect(io.string).not_to include('┌')
    expect(spec.run_dir.join('GroundAdvantage_shipper_rate.csv')).to exist
  end

  it 'reports where the files were saved' do
    report(spec_in(@dir), good_client).run

    expect(io.string).to include('Saved 1 file')
    expect(io.string).to include('GroundAdvantage_shipper_rate.csv')
  end

  it 'returns 0 and still writes files on a partially failed run' do
    client = FakeClient.new do |weight, _postal|
      weight == 2 ? RateCard::RequestFailed.new('HTTP 500') : { 'service_rates' => [{ 'service_id' => 1172, 'rate' => 1.0 }] }
    end
    spec = spec_in(@dir)

    expect(report(spec, client).run).to eq(0)
    expect(spec.run_dir.join('GroundAdvantage_shipper_rate.csv')).to exist
    expect(io.string).to include('cells failed')
  end

  it 'returns 1 with a selection-focused message when calls succeeded but priced nothing' do
    client = FakeClient.new { |_w, _p| { 'service_rates' => [] } }
    spec = spec_in(@dir)

    expect(report(spec, client).run).to eq(1)
    expect(io.string).to include('no rates for the selected')
    expect(io.string).not_to include('every rate call failed')
    expect(spec.run_dir).not_to exist
  end

  it 'returns 1 and writes no files when every call failed' do
    client = FakeClient.new { |_w, _p| RateCard::RequestFailed.new('down') }
    spec = spec_in(@dir)

    expect(report(spec, client).run).to eq(1)
    expect(spec.run_dir).not_to exist
  end

  # The docs: a carrier failure comes back as a 201 with a populated warnings
  # array. Without reporting it, the user gets blank cells and no reason.
  it 'reports the API warnings from a call that otherwise succeeded' do
    client = FakeClient.new do |weight, _postal|
      { 'service_rates' => [{ 'service_id' => 1172, 'rate' => weight * 1.0 }],
        'warnings' => ['FedEx returned error: Destination postal code missing or invalid'] }
    end

    report(spec_in(@dir), client).run

    expect(io.string).to include('Destination postal code missing or invalid')
  end

  it 'explains a card of blank cells with the warnings that came back with it' do
    client = FakeClient.new do |_weight, _postal|
      { 'service_rates' => [], 'warnings' => ['USPS returned error: service not enabled'] }
    end

    code = report(spec_in(@dir), client).run

    expect(code).to eq(1)
    expect(io.string).to include('service not enabled')
  end
end
