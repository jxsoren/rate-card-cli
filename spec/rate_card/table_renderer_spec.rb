# frozen_string_literal: true

require 'pathname'

RSpec.describe RateCard::TableRenderer do
  let(:ground) do
    RateCard::Service.new(id: 1172, code: 'GroundAdvantage', name: 'USPS Ground Advantage',
                          carrier: 'USPS')
  end

  let(:spec) do
    RateCard::RunSpec.new(
      token: 'tok', customer_name: 'Acme Fulfillment', customer_id: 1042, carrier: 'USPS',
      services: [ground], zones: [1, 2], weight_unit: :oz, weights: [1, 2],
      package_type: 'parcel', rate_keys: %i[shipper_rate meter_rate],
      output_base: Pathname.new('/tmp'), show_table: true, started_at: Time.now
    )
  end

  let(:grid) do
    RateCard::Grid.new(spec).tap do |g|
      cells = g.instance_variable_get(:@cells)
      cells[[1172, :shipper_rate, 1, 1]] = 5.85
      cells[[1172, :shipper_rate, 1, 2]] = 6.15
      cells[[1172, :shipper_rate, 2, 1]] = 7.0
      cells[[1172, :shipper_rate, 2, 2]] = nil
      cells[[1172, :meter_rate, 1, 1]] = 6.9
      cells[[1172, :meter_rate, 1, 2]] = 7.25
      cells[[1172, :meter_rate, 2, 1]] = 8.0
      cells[[1172, :meter_rate, 2, 2]] = nil
    end
  end

  subject(:tables) { described_class.new(grid: grid, spec: spec).tables }

  it 'returns one entry per service per rate key' do
    expect(tables.length).to eq(2)
  end

  it 'titles each table with customer, service and rate key' do
    expect(tables.first[0])
      .to eq('Acme Fulfillment (1042) · USPS Ground Advantage · shipper rate')
  end

  it 'orders tables by rate key as selected' do
    expect(tables.map { |title, _| title }.last).to include('meter rate')
  end

  it 'heads the first column with the weight unit' do
    expect(tables.first[1]).to include('wt(oz)')
  end

  it 'heads a column per zone' do
    rendered = tables.first[1]

    expect(rendered).to include('Z1')
    expect(rendered).to include('Z2')
  end

  it 'formats rates to two decimal places' do
    expect(tables.first[1]).to include('5.85')
    expect(tables.first[1]).to include('7.00')
  end

  it 'renders a nil cell as an em dash, never as a zero' do
    rendered = tables.first[1]

    expect(rendered).to include('—')
    expect(rendered).not_to include('0.00')
  end

  it 'draws the same rounded border the TUI banner uses' do
    expect(tables.first[1]).to include('╭')
  end

  it 'right-aligns the cells so the decimal points line up' do
    # Two rates of different widths land flush against the same column edge.
    rendered = tables.first[1]

    expect(rendered).to match(/│\s+5\.85 │/)
    expect(rendered).to match(/│\s+— │/)
  end

  describe '#rows' do
    it 'exposes the underlying rows for one table' do
      rows = described_class.new(grid: grid, spec: spec).rows(ground, :shipper_rate)

      expect(rows).to eq([['1', '5.85', '6.15'], ['2', '7.00', '—']])
    end
  end

  describe 'cubic mode' do
    let(:cubic_spec) do
      RateCard::RunSpec.new(
        token: 'tok', customer_name: 'Acme Fulfillment', customer_id: 1042, carrier: 'USPS',
        services: [ground], zones: [1], weight_unit: :oz, weights: [],
        rate_mode: :cubic, cubic_tiers: [1, 2], package_type: 'parcel',
        rate_keys: [:shipper_rate], output_base: Pathname.new('/tmp'), show_table: true,
        started_at: Time.now
      )
    end

    let(:cubic_grid) do
      RateCard::Grid.new(cubic_spec).tap do |g|
        cells = g.instance_variable_get(:@cells)
        cells[[1172, :shipper_rate, 1, 1]] = 4.2
        cells[[1172, :shipper_rate, 2, 1]] = 5.4
      end
    end

    it 'heads the row column "cubic tier" and labels rows by tier name' do
      rendered = described_class.new(grid: cubic_grid, spec: cubic_spec).tables.first[1]

      expect(rendered).to include('cubic tier')
      expect(rendered).to include('Tier 1')
      expect(rendered).to include('Tier 2')
    end
  end
end
