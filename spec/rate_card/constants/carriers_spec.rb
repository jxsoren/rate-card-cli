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

    it 'names an unrecognised carrier by its own code rather than Other' do
      expect(described_class.for_carrier_code('ontrac')).to eq('ONTRAC')
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
end
