# frozen_string_literal: true

RSpec.describe RateCard::Providers::EHub::ServiceCatalog do
  let(:body) do
    { 'services' => [
      { 'service_id' => 1172, 'service_code' => 'GroundAdvantage',
        'service' => 'USPS Ground Advantage', 'carrier_code' => 'usps', 'category' => 'shipping' },
      { 'service_id' => 392, 'service_code' => 'FEDEX_GROUND',
        'service' => 'FedEx Ground', 'carrier_code' => 'fedex', 'category' => 'shipping' },
      { 'service_id' => 999_999, 'service_code' => 'MYSTERY',
        'service' => 'Mystery Service', 'category' => 'shipping' }
    ] }
  end

  describe '.from_response' do
    it 'builds a Service per entry' do
      services = described_class.from_response(body)

      expect(services.map(&:id)).to contain_exactly(1172, 392, 999_999)
    end

    it 'carries the package types the service reports' do
      body['services'][0]['package_types'] = [
        { 'type' => 'fedex_pak', 'name' => 'FedEx Pak' },
        { 'type' => 'parcel', 'name' => 'Parcel' }
      ]

      service = described_class.from_response(body).find { |s| s.id == 1172 }

      expect(service.package_types).to eq(%w[fedex_pak parcel])
    end

    it 'reports no package types rather than nil when the service lists none' do
      expect(described_class.from_response(body).first.package_types).to eq([])
    end

    it 'resolves carrier from the carrier_code the services endpoint reports' do
      services = described_class.from_response(body)

      expect(services.find { |s| s.id == 1172 }.carrier).to eq('USPS')
      expect(services.find { |s| s.id == 392 }.carrier).to eq('FedEx')
    end

    it 'names an unrecognised carrier_code by itself rather than lumping it into Other' do
      body['services'][2]['carrier_code'] = 'ontrac'

      expect(described_class.from_response(body).find { |s| s.id == 999_999 }.carrier)
        .to eq('ONTRAC')
    end

    it 'groups a service whose carrier_code is missing under Other rather than dropping it' do
      mystery = described_class.from_response(body).find { |s| s.id == 999_999 }

      expect(mystery.carrier).to eq('Other')
      expect(mystery.name).to eq('Mystery Service')
    end

    it 'treats a blank carrier_code as missing' do
      body['services'][0]['carrier_code'] = '  '

      expect(described_class.from_response(body).find { |s| s.id == 1172 }.carrier).to eq('Other')
    end

    it 'falls back to the service code when there is no display name' do
      response = { 'services' => [{ 'service_id' => 1172, 'service_code' => 'GroundAdvantage' }] }

      expect(described_class.from_response(response).first.name).to eq('GroundAdvantage')
    end

    it 'de-duplicates repeated service ids' do
      response = { 'services' => [
        { 'service_id' => 1172, 'service_code' => 'GA', 'service' => 'GA' },
        { 'service_id' => 1172, 'service_code' => 'GA', 'service' => 'GA' }
      ] }

      expect(described_class.from_response(response).length).to eq(1)
    end

    it 'sorts by carrier display order, then by name' do
      names = described_class.from_response(body).map(&:carrier)

      expect(names).to eq(%w[USPS FedEx Other])
    end

    it 'skips entries with no service_id' do
      response = { 'services' => [{ 'service_code' => 'GA' }] }

      expect(described_class.from_response(response)).to be_empty
    end

    it 'returns an empty array when services is missing' do
      expect(described_class.from_response({})).to eq([])
    end
  end

  describe '.group_by_carrier' do
    it 'returns carrier => services in display order' do
      grouped = described_class.group_by_carrier(described_class.from_response(body))

      expect(grouped.keys).to eq(%w[USPS FedEx Other])
      expect(grouped['USPS'].first.id).to eq(1172)
    end
  end
end
