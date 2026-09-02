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

    # DHL eCommerce's zone calculator in ehub is an unmodified subclass of
    # USPS's (app/services/carriers/dhl_ecommerce/zone_calculator.rb), so
    # DHL eCommerce zones are USPS zones - this is the same chart, not a
    # coincidence to keep in sync by hand.
    it 'returns the USPS chart for DHL, since DHL eCommerce zones are USPS zones' do
      expect(described_class.for_carrier('DHL')).to eq(described_class.for_carrier('USPS'))
    end

    # OSM's zone calculator in ehub is likewise an unmodified subclass of
    # USPS's (app/services/carriers/osm/zone_calculator.rb), so OSM zones
    # are USPS zones too.
    it 'returns the USPS chart for OSM, since OSM zones are USPS zones' do
      expect(described_class.for_carrier('OSM')).to eq(described_class.for_carrier('USPS'))
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

    it 'lists zones 1-8 for DHL, same as USPS' do
      expect(described_class.available_zones('DHL')).to eq((1..8).to_a)
    end

    it 'lists zones 1-8 for OSM, same as USPS' do
      expect(described_class.available_zones('OSM')).to eq((1..8).to_a)
    end
  end

  describe '.supported?' do
    it 'is true only for a carrier we hold a chart for' do
      expect(described_class.supported?('USPS')).to be(true)
      expect(described_class.supported?('DHL')).to be(true)
      expect(described_class.supported?('OSM')).to be(true)
      expect(described_class.supported?('Nonesuch')).to be(false)
    end
  end

  describe 'USPS_RURAL_DAS' do
    it 'has a rural surcharge test address for zones 0-8' do
      expect(described_class::USPS_RURAL_DAS.keys).to eq((0..8).to_a)
    end

    it 'gives every address the fields a request payload needs' do
      described_class::USPS_RURAL_DAS.each_value do |address|
        expect(address.keys).to include(:address1, :city, :state, :postal_code, :country)
      end
    end
  end

  describe 'UPS_EDAS_EXCEPTION' do
    it 'is a single complete address' do
      expect(described_class::UPS_EDAS_EXCEPTION)
        .to include(:address1, :city, :state, :postal_code, :country)
    end
  end

  describe 'UPS_RDAS_EXCEPTION' do
    it 'is a single complete address' do
      expect(described_class::UPS_RDAS_EXCEPTION)
        .to include(:address1, :city, :state, :postal_code, :country)
    end
  end
end
