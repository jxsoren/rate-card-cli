# frozen_string_literal: true

RSpec.describe RateCard::ServiceCatalog do
  let(:body) do
    { 'service_rates' => [
      { 'service_id' => 1172, 'service_code' => 'GroundAdvantage',
        'service' => 'USPS Ground Advantage', 'rate' => 5.85, 'meter_rate' => 6.9 },
      { 'service_id' => 392, 'service_code' => 'FEDEX_GROUND',
        'service' => 'FedEx Ground', 'rate' => 9.1, 'meter_rate' => 11.0 },
      { 'service_id' => 999_999, 'service_code' => 'MYSTERY',
        'service' => 'Mystery Service', 'rate' => 1.0, 'meter_rate' => 1.0 }
    ] }
  end

  describe '.from_response' do
    it 'builds a Service per entry' do
      services = described_class.from_response(body)

      expect(services.map(&:id)).to contain_exactly(1172, 392, 999_999)
    end

    it 'resolves carrier from the service id map' do
      services = described_class.from_response(body)

      expect(services.find { |s| s.id == 1172 }.carrier).to eq('USPS')
      expect(services.find { |s| s.id == 392 }.carrier).to eq('FedEx')
    end

    it 'groups an unrecognised service id under Other instead of dropping it' do
      mystery = described_class.from_response(body).find { |s| s.id == 999_999 }

      expect(mystery.carrier).to eq('Other')
      expect(mystery.name).to eq('Mystery Service')
    end

    it 'prefers an explicit carrier field when the response provides one' do
      body['service_rates'][0]['carrier'] = 'USPS-DAP'

      expect(described_class.from_response(body).find { |s| s.id == 1172 }.carrier).to eq('USPS-DAP')
    end

    it 'falls back to the service code when there is no display name' do
      response = { 'service_rates' => [{ 'service_id' => 1172, 'service_code' => 'GroundAdvantage' }] }

      expect(described_class.from_response(response).first.name).to eq('GroundAdvantage')
    end

    it 'de-duplicates repeated service ids' do
      response = { 'service_rates' => [
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
      response = { 'service_rates' => [{ 'service_code' => 'GA' }] }

      expect(described_class.from_response(response)).to be_empty
    end

    it 'returns an empty array when service_rates is missing' do
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
