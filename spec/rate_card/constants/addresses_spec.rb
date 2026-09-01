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

    it 'raises for a carrier with no curated zone chart rather than defaulting' do
      expect { described_class.for_carrier('Nonesuch') }
        .to raise_error(RateCard::UnsupportedCarrier, /no curated zone chart for Nonesuch/)
    end

    # The regression this replaced: 'dhl_ecommerce' upcased to a carrier name
    # in no table, and the USPS fallback then priced DHL against USPS zones.
    it 'raises for DHL, which has no chart yet, instead of returning USPS' do
      expect { described_class.for_carrier('DHL') }.to raise_error(RateCard::UnsupportedCarrier)
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

    it 'is empty for a carrier with no chart, so callers need no rescue' do
      expect(described_class.available_zones('DHL')).to eq([])
    end
  end

  describe '.supported?' do
    it 'is true only for a carrier we hold a chart for' do
      expect(described_class.supported?('USPS')).to be(true)
      expect(described_class.supported?('DHL')).to be(false)
    end
  end
end
