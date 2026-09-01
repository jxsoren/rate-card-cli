# frozen_string_literal: true

require 'pathname'

RSpec.describe RateCard::Shipment do
  def spec_for(unit)
    RateCard::RunSpec.new(
      token: 'tok', customer_name: 'Acme', customer_id: 1,
      carrier: 'USPS',
      services: [RateCard::Service.new(id: 1172, code: 'GA', name: 'GA', carrier: 'USPS')],
      zones: [1], weight_unit: unit, weights: [2], package_type: 'parcel',
      rate_keys: [:shipper_rate], output_base: Pathname.new('/tmp'),
      show_table: true, started_at: Time.now
    )
  end

  let(:address) do
    { address1: '1206 W 9440 S', city: 'South Jordan', state: 'UT',
      postal_code: '84094', country: 'US' }
  end

  subject(:payload) { described_class.new(spec: spec_for(:oz), weight: 4, address: address).payload }

  it 'nests everything under a shipment key' do
    expect(payload.keys).to eq([:shipment])
  end

  it 'uses the curated origin as from_location' do
    expect(payload[:shipment][:from_location]).to include(postal_code: '84070', country: 'US')
  end

  it 'uses the given zone address as to_location' do
    expect(payload[:shipment][:to_location]).to include(postal_code: '84094', city: 'South Jordan')
  end

  it 'requests basic address validation so a curated address is not rejected' do
    expect(payload[:shipment][:to_location][:validation_level]).to eq('basic')
  end

  it 'sends exactly one parcel with the selected package type' do
    parcels = payload[:shipment][:parcels]

    expect(parcels.length).to eq(1)
    expect(parcels.first[:package_type]).to eq('parcel')
  end

  it 'sends the weight in ounces when the unit is oz' do
    expect(payload[:shipment][:parcels].first[:weight]).to eq(4)
  end

  it 'converts the weight to ounces when the unit is lbs' do
    lbs = described_class.new(spec: spec_for(:lbs), weight: 4, address: address).payload

    expect(lbs[:shipment][:parcels].first[:weight]).to eq(64)
  end

  it 'includes a parcel item with customs data so international services do not error' do
    item = payload[:shipment][:parcels].first[:parcel_items].first

    expect(item).to include(:name, :quantity, :price)
    expect(item[:customs_data]).to include(content_type: 'merchandise')
  end

  it 'sends fixed nominal dimensions' do
    parcel = payload[:shipment][:parcels].first

    expect(parcel.values_at(:length, :width, :height)).to eq([2, 2, 2])
  end

  it 'is JSON-serialisable' do
    expect { JSON.generate(payload) }.not_to raise_error
  end
end
