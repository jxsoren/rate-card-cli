# frozen_string_literal: true

RSpec.describe RateCard::Constants::Addresses do
  describe '.for_carrier' do
    it 'returns a zone-keyed hash of addresses for USPS' do
      addresses = described_class.for_carrier('USPS')

      expect(addresses.keys).to eq((1..8).to_a)
      expect(addresses[1]).to include(city: 'South Jordan', postal_code: '84094')
    end

    it 'returns UPS-specific addresses, which differ from USPS in zone 1' do
      expect(described_class.for_carrier('UPS')[1][:postal_code]).to eq('84094')
      expect(described_class.for_carrier('UPS')[1][:address1])
        .not_to eq(described_class.for_carrier('USPS')[1][:address1])
    end

    it 'returns FedEx-specific addresses' do
      expect(described_class.for_carrier('FedEx')[1]).to include(city: 'Salt Lake City')
    end

    it 'falls back to the USPS table for an unknown carrier' do
      expect(described_class.for_carrier('Nonesuch')).to eq(described_class.for_carrier('USPS'))
    end

    it 'gives every address the fields a request payload needs' do
      described_class.for_carrier('USPS').each_value do |address|
        expect(address.keys).to include(:address1, :city, :state, :postal_code, :country)
      end
    end
  end

  describe 'ORIGIN' do
    it 'is a complete shippable origin address' do
      expect(described_class::ORIGIN)
        .to include(:address1, :city, :state, :postal_code, :country)
    end
  end

  describe '.available_zones' do
    it 'lists the zones a carrier can be asked for' do
      expect(described_class.available_zones('USPS')).to eq((1..8).to_a)
    end
  end
end
