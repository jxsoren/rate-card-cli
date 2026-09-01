# frozen_string_literal: true

require 'pathname'
require 'tmpdir'

RSpec.describe RateCard::CsvWriter do
  let(:ground) do
    RateCard::Service.new(id: 1172, code: 'GroundAdvantage', name: 'GA', carrier: 'USPS')
  end

  def spec_in(dir, rate_keys: %i[shipper_rate meter_rate], services: [ground])
    RateCard::RunSpec.new(
      token: 'tok', customer_name: 'Acme', customer_id: 1042, carrier: 'USPS',
      services: services, zones: [1, 2], weight_unit: :oz, weights: [1, 2],
      package_type: 'parcel', rate_keys: rate_keys,
      output_base: Pathname.new(dir), show_table: true,
      started_at: Time.utc(2026, 8, 31, 15, 4, 22)
    )
  end

  # A grid with a known hole at weight 2, zone 2.
  def grid_for(spec)
    grid = RateCard::Grid.new(spec)
    values = { [1, 1] => 5.85, [1, 2] => 6.15, [2, 1] => 7.0, [2, 2] => nil }
    cells = grid.instance_variable_get(:@cells)
    spec.services.each do |service|
      spec.rate_keys.each do |key|
        values.each do |(weight, zone), value|
          cells[[service.id, key, weight, zone]] = value
        end
      end
    end
    grid
  end

  around do |example|
    Dir.mktmpdir { |dir| @dir = dir; example.run }
  end

  it 'writes one file per service per rate key' do
    spec = spec_in(@dir)
    paths = described_class.new(grid: grid_for(spec), spec: spec).write

    expect(paths.map { |p| p.basename.to_s })
      .to contain_exactly('GroundAdvantage_shipper_rate.csv', 'GroundAdvantage_meter_rate.csv')
  end

  it 'writes into the timestamped run directory' do
    spec = spec_in(@dir)
    paths = described_class.new(grid: grid_for(spec), spec: spec).write

    expect(paths.first.dirname.basename.to_s).to eq('acme_1042_2026-08-31T15-04-22Z')
  end

  it 'creates the run directory if it does not exist' do
    spec = spec_in(File.join(@dir, 'nested', 'deeper'))

    expect { described_class.new(grid: grid_for(spec), spec: spec).write }.not_to raise_error
  end

  it 'writes a weight column plus one column per zone' do
    spec = spec_in(@dir)
    paths = described_class.new(grid: grid_for(spec), spec: spec).write
    content = File.read(paths.find { |p| p.to_s.include?('shipper') })

    expect(content.lines.first.chomp).to eq('weight,1,2')
  end

  it 'writes one row per weight in the requested order' do
    spec = spec_in(@dir)
    paths = described_class.new(grid: grid_for(spec), spec: spec).write
    content = File.read(paths.find { |p| p.to_s.include?('shipper') })

    expect(content).to eq("weight,1,2\n1,5.85,6.15\n2,7.0,\n")
  end

  it 'writes an empty field for a nil cell, never 0.0' do
    spec = spec_in(@dir)
    paths = described_class.new(grid: grid_for(spec), spec: spec).write
    content = File.read(paths.find { |p| p.to_s.include?('shipper') })

    expect(content).to include("2,7.0,\n")
    expect(content).not_to include('0.0')
  end

  it 'writes only the selected rate keys' do
    spec = spec_in(@dir, rate_keys: [:shipper_rate])
    paths = described_class.new(grid: grid_for(spec), spec: spec).write

    expect(paths.length).to eq(1)
  end

  it 'names files from the service code, sanitised' do
    odd = RateCard::Service.new(id: 9, code: 'UPS 2nd Day Air®', name: 'x', carrier: 'UPS')
    spec = spec_in(@dir, rate_keys: [:shipper_rate], services: [odd])
    paths = described_class.new(grid: grid_for(spec), spec: spec).write

    expect(paths.first.basename.to_s).to eq('UPS_2nd_Day_Air_shipper_rate.csv')
  end

  describe '.ensure_writable!' do
    it 'passes for a writable base directory' do
      expect { described_class.ensure_writable!(Pathname.new(@dir)) }.not_to raise_error
    end

    it 'passes for a base directory that does not exist but can be created' do
      expect { described_class.ensure_writable!(Pathname.new(File.join(@dir, 'new'))) }
        .not_to raise_error
    end

    it 'raises OutputNotWritable when the base cannot be created' do
      File.write(File.join(@dir, 'afile'), 'x')

      expect { described_class.ensure_writable!(Pathname.new(File.join(@dir, 'afile', 'sub'))) }
        .to raise_error(RateCard::OutputNotWritable)
    end
  end
end
