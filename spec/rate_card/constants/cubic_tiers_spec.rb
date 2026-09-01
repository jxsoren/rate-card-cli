# frozen_string_literal: true

RSpec.describe RateCard::Constants::CubicTiers do
  describe '::TIERS' do
    it 'has the ten official USPS cubic tiers, ascending in size' do
      expect(described_class::TIERS.map { |t| t[:tier] }).to eq((1..10).to_a)
      lengths = described_class::TIERS.map { |t| t[:length] }
      expect(lengths).to eq(lengths.sort)
    end

    it 'caps tiers 1-8 at 128oz (8lb) and tiers 9-10 at 240oz (15lb)' do
      expect(described_class::TIERS.first(8).map { |t| t[:weight_oz] }).to all(eq(128))
      expect(described_class::TIERS.last(2).map { |t| t[:weight_oz] }).to all(eq(240))
    end
  end

  describe '.ids' do
    it 'lists tier ids 1 through 10' do
      expect(described_class.ids).to eq((1..10).to_a)
    end
  end

  describe '.dims' do
    it 'returns the length/width/height for a known tier' do
      expect(described_class.dims(1)).to eq(length: 3.0, width: 3.0, height: 3.0)
    end

    it 'returns nil for an unknown tier' do
      expect(described_class.dims(99)).to be_nil
    end
  end

  describe '.weight_oz' do
    it 'returns the weight cap for a known tier' do
      expect(described_class.weight_oz(1)).to eq(128)
      expect(described_class.weight_oz(9)).to eq(240)
    end
  end

  describe '.label' do
    it 'names a tier for display' do
      expect(described_class.label(3)).to eq('Tier 3')
    end
  end

  describe '.choices' do
    it 'returns one [display, tier_id] pair per tier' do
      choices = described_class.choices

      expect(choices.length).to eq(10)
      expect(choices.map(&:last)).to eq((1..10).to_a)
      expect(choices.first.first).to eq('Tier 1 — 3x3x3in, ≤8lb')
      expect(choices.last.first).to eq('Tier 10 — 11.75x11.75x11.75in, ≤15lb')
    end
  end
end
