# frozen_string_literal: true

RSpec.describe RateCard::Constants::Carriers do
  describe '.for_carrier_code' do
    it 'maps a known lowercase code to its display name' do
      expect(described_class.for_carrier_code('usps')).to eq('USPS')
      expect(described_class.for_carrier_code('fedex')).to eq('FedEx')
    end

    it 'is indifferent to case and surrounding whitespace' do
      expect(described_class.for_carrier_code(' USPS ')).to eq('USPS')
    end

    # 'dhl_ecommerce' used to upcase to 'DHL_ECOMMERCE', which matched no zone
    # chart and fell back to USPS addresses — accidentally right, for the
    # wrong reason. It's now deliberately aliased to USPS via 'DHL' below.
    it 'maps dhl_ecommerce to the DHL display carrier' do
      expect(described_class.for_carrier_code('dhl_ecommerce')).to eq('DHL')
    end

    # Bare 'dhl' is DHL Express, a distinct carrier with unverified zones —
    # it must not share the 'DHL' key (and its USPS alias) with dhl_ecommerce.
    it 'maps bare dhl to a distinct display carrier' do
      expect(described_class.for_carrier_code('dhl')).to eq('DHL Express')
    end

    it 'maps osm to its own display carrier' do
      expect(described_class.for_carrier_code('osm')).to eq('OSM')
    end

    it 'names an unrecognised carrier by its own code rather than Other' do
      expect(described_class.for_carrier_code('ontrac')).to eq('ONTRAC')
    end

    it 'maps the 6 live-chart carrier codes to their display names' do
      expect(described_class.for_carrier_code('cdl')).to eq('CDL')
      expect(described_class.for_carrier_code('gls')).to eq('GLS')
      expect(described_class.for_carrier_code('speedx')).to eq('SpeedX')
      expect(described_class.for_carrier_code('uniuni')).to eq('UniUni')
      expect(described_class.for_carrier_code('veho')).to eq('Veho')
      expect(described_class.for_carrier_code('dragonfly')).to eq('Dragonfly')
    end

    it 'falls back to Other only when the code is missing or blank' do
      expect(described_class.for_carrier_code(nil)).to eq('Other')
      expect(described_class.for_carrier_code('   ')).to eq('Other')
    end
  end

  describe '.display_order' do
    it 'ranks Other last' do
      expect(described_class.display_order.last).to eq('Other')
    end

    # Named directly rather than derived from CARRIER_CODES: deriving the
    # display order from the mapping would let a new code silently reorder the
    # carrier menu.
    it 'names the carriers we actually build cards for' do
      expect(described_class.display_order).to include('USPS', 'FedEx')
    end
  end

  describe '.rural_aware?' do
    it 'is true for USPS and UPS, false for everything else' do
      expect(described_class.rural_aware?('USPS')).to be(true)
      expect(described_class.rural_aware?('UPS')).to be(true)
      expect(described_class.rural_aware?('FedEx')).to be(false)
      expect(described_class.rural_aware?('Nonesuch')).to be(false)
    end
  end

  describe '.live_chart?' do
    it 'is true for the 6 live-chart carriers' do
      %w[CDL GLS SpeedX UniUni Veho Dragonfly].each do |carrier|
        expect(described_class.live_chart?(carrier)).to be(true)
      end
    end

    it 'is false for a static-chart carrier and for OLX' do
      expect(described_class.live_chart?('USPS')).to be(false)
      expect(described_class.live_chart?('OLX')).to be(false)
    end
  end
end
